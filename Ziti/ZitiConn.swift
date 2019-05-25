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
    let regulator = TransferRegulator(0xffff0) // TODO: What's right value. Start with maxWndScale << 1
    
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
            //let data = Data(bytesNoCopy: buf!, count: Int(nBytes), deallocator: .none) // TODO: CHICKEN DINNER!
            let data = Data(bytes: buf!, count: Int(nBytes)) // bytes no copy is mem error when ziti sdk frees buff before we write
            mySelf.onDataAvailable?(data, Int(nBytes))
        } else {
            let errStr = String(cString: ziti_errorstr(nBytes))
            NSLog("ZitiConn \"\(errStr)\" \(mySelf.key).")
            
            if mySelf.closeWait { 
                mySelf.releaseConnection?()
            } else {
                mySelf.closeWait = true
                
                // give delegate a chance to clean-up
                mySelf.onDataAvailable?(nil, Int(nBytes))
            }
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
        
        if !regulator.wait(payload.count, 1.0) {
            NSLog("Ziti conn timed out waiting for ziti write window \(key)")
            // if lose network, scheduled close doesn't happen.  Return -1 instead and leave closing to other side...
            // zid.scheduleOp { self.close() }
            return -1
        } else {
            zid.scheduleOp {
                guard self.closeWait == false else { print("closeWait drop write"); return }
                
                // TODO: figure out how to avoid the copy (making payload optional would help)
                let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
                ptr.initialize(from: [UInt8](payload), count: payload.count)
                let status = NF_write(self.nfConn, ptr, payload.count)
                ptr.deallocate()
                
                // TODO: This should be in (coming soon) on_nf_write_complete callback...
                // at that point try calling from current thread (if try that now there is 0 throttle...)
                self.regulator.decPending(payload.count)
                
                if status != ZITI_OK {
                    let errStr = String(cString: ziti_errorstr(status))
                    NSLog("ZitiConn \(self.key) Error writing: \(errStr)")
                    return // -1
                }
            }
        }
        return payload.count // TODO: bogus
    }
    
    func close() {
        zid.scheduleOp { [weak self] in
            if self?.closeWait ?? false {
                self?.releaseConnection?()
            } else if let mySelf = self, mySelf.nfConn != nil {
                NSLog("ZitiConn closing \(mySelf.key)")
                self?.closeWait = true
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
