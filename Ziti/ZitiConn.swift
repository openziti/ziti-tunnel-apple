//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class ZitiConn : NSObject, ZitiClientProtocol {
    var onDataAvailable:DataAvailableCallback?
    var releaseConnection:(()->Void)?
    
    let key:String
    let zid:ZitiIdentity
    let svc:ZitiEdgeService
    
    let writeCond = NSCondition()
    var okToWrite = false
    
    var nfConn:nf_connection?
    var closeWait = false
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService) {
        self.key = key
        self.zid = zid
        self.svc = svc
        
        super.init()
        NSLog("init ZitiConn \(key)")
    }
    
    deinit {
        NSLog("deinit ZitiConn \(key)")
    }
    
    static let on_nf_conn:nf_conn_cb = { nfConn, status in
        guard let mySelf = ZitiConn.fromContext(NF_conn_data(nfConn)) else {
            NSLog("ZitiConn.onConn WTF invalid ctx")
            return
        }
        print("ZitiConn.onConn OK to write \(mySelf.key)")
        mySelf.okToWrite = true
        mySelf.writeCond.signal()
    }
    
    static let on_nf_data:nf_data_cb = { nfConn, buf, nBytes in
        guard let nfConn = nfConn, let mySelf = ZitiConn.fromContext(NF_conn_data(nfConn)) else {
            NSLog("ZitiConn.onData WTF invalid ctx")
            return
        }
        
        if nBytes > 0 && buf != nil {
            let data = Data(bytesNoCopy: buf!, count: Int(nBytes), deallocator: .none)
            mySelf.onDataAvailable?(data, Int(nBytes))
        } else {
            mySelf.closeWait = true
            
            // give delegate a chance to clean-up
            mySelf.onDataAvailable?(nil, Int(nBytes))
            
            let errStr = String(cString: ziti_errorstr(nBytes))
            NSLog("ZitiConn \"\(errStr)\".")
        }
    }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        NSLog("ZitiConn connect \(key)")
        self.onDataAvailable = onDataAvailable
        
        // validate the service
        guard let svcName_c = svc.name?.cString(using: .utf8) else {
            NSLog("ZitiConn \(key) Unable to create C service name for \(zid.id):\(svc.name ?? "nil")")
            return false
        }
        
        zid.scheduleOp {
            // init the connection
            var status = NF_conn_init(self.zid.nf_context, &self.nfConn, self.toVoidPtr())
            guard  status == ZITI_OK else {
                let errStr = String(cString: ziti_errorstr(status))
                NSLog("ZitiConn \(self.key) Unable to initiate connection for \(self.zid.id):\(self.svc.name ?? "nil"), \(errStr)")
                return // false
            }
        
            // dial it
            NSLog("                 DIALING")
            status = NF_dial(self.nfConn, svcName_c, ZitiConn.on_nf_conn, ZitiConn.on_nf_data)
            guard status == ZITI_OK else {
                let errStr = String(cString: ziti_errorstr(status))
                NSLog("ZitiConn \(self.key) Unable to dial service \(self.zid.id):\(self.svc.name ?? "nil"), \(errStr)")
                return // false
            }
        }
    
        return true
    }
    
    func write(payload:Data) -> Int {
        writeCond.lock()
        while !okToWrite {
            if !writeCond.wait(until: Date(timeIntervalSinceNow: 5.0)) {
                NSLog("*** ZitiConn \(key) timed out waiting for ziti connection callback")
                writeCond.unlock()
                return -1
            }
        }
        writeCond.unlock()
        
        zid.scheduleOp {
            guard self.closeWait == false else { return }
            
            // TODO: figure out how to avoid the copy (making payload optional would help)
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
            ptr.initialize(from: [UInt8](payload), count: payload.count)
            let status = NF_write(self.nfConn, ptr, payload.count)
            ptr.deallocate()
            
            if status != ZITI_OK {
                let errStr = String(cString: ziti_errorstr(status))
                NSLog("ZitiConn \(self.key) Error writing: \(errStr)")
                return // -1
            }
        }
        return payload.count
    }
    
    func close() {
        print("scheduling ziti close")
        zid.scheduleOp { [weak self] in
            print("executing ziti close")
            if self?.closeWait ?? false {
                print("Already closing. Release connection") // TODO: still not quire right.  Should be from socketDidClose only
                self?.releaseConnection?()
            } else if let mySelf = self, mySelf.nfConn != nil {
                NSLog("ZitiConn closing \(mySelf.key)")
                let status = NF_close(&mySelf.nfConn)
                if status != ZITI_OK {
                    let errStr = String(cString: ziti_errorstr(status))
                    NSLog("ZitiConn.close error for \(mySelf.key), \(errStr)")
                }
                mySelf.nfConn = nil
            }
        }
    }
    
    static func fromContext(_ ctx:Optional<UnsafeMutableRawPointer>) -> ZitiConn? {
        guard ctx != nil else { return nil }
        return Unmanaged<ZitiConn>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
    }
    
    func toVoidPtr() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }
}
