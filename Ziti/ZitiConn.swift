//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class ZitiConn : NSObject, ZitiClientProtocol {
    var onDataAvailable:DataAvailableCallback?
    var releaseConnection:(()->Void)?
    
    class OnWriteData {
        let ptr:UnsafeMutablePointer<UInt8>
        let mySelf:ZitiConn
        let len:Int
        init(_ ptr:UnsafeMutablePointer<UInt8>, _ len:Int, _ mySelf:ZitiConn) {
            self.ptr = ptr
            self.len = len
            self.mySelf = mySelf
        }
        
        static func fromContext(_ ctx:Optional<UnsafeMutableRawPointer>) -> OnWriteData? {
            guard ctx != nil else { return nil }
            return Unmanaged<OnWriteData>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
        }
        
        func toVoidPtr() -> UnsafeMutableRawPointer {
            return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        }
    }
    var writeQueue:[OnWriteData] = []
    
    var key:String
    let zid:ZitiIdentity
    let svc:ZitiEdgeService
    
    let writeCond = NSCondition()
    var okToWrite = false
    var connectFailed = false
    weak var regulator:TransferRegulator?
    var waitQueue = DispatchQueue(label: "ZitiWaitQueue", attributes: [])
    
    var nfConn:nf_connection?
    var closeWait = false
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService, _ tr:TransferRegulator) {
        self.key = key
        self.zid = zid
        self.svc = svc
        regulator = tr //TransferRegulator(0xffff0, "ZitiRegulator\(key)") // TODO: What's right value. Start with maxWndScale << 1
        
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
    
        mySelf.writeCond.lock()
        if status == ZITI_OK {
            //print("ZitiConn.onConn OK to write \(mySelf.key)")
            mySelf.okToWrite = true
        } else {
            let errStr = String(cString: ziti_errorstr(status))
            NSLog("ZitiConn.onConn error \"\(errStr)\" \(mySelf.key)")
            mySelf.closeWait = true
            mySelf.connectFailed = true
        }
        mySelf.writeCond.signal()
        mySelf.writeCond.unlock()
    }
    
    static let on_nf_data:nf_data_cb = { nfConn, buf, nBytes in
        guard let nfConn = nfConn, let ctx = NF_conn_data(nfConn), let mySelf = ZitiConn.fromContext(ctx) else {
            NSLog("ZitiConn.onData WTF invalid ctx")
            return
        }
        
        if nBytes > 0 && buf != nil {
            let data = Data(bytes: buf!, count: Int(nBytes))
            mySelf.onDataAvailable?(data, Int(nBytes))
        } else {
            
            if nBytes != ZITI_EOF {
                let errStr = String(cString: ziti_errorstr(nBytes))
                NSLog("ZitiConn.onData error \"\(errStr)\" \(mySelf.key).")
            }
            
            if mySelf.closeWait {
                mySelf.releaseConnection?()
            } else {
                mySelf.closeWait = true
                mySelf.onDataAvailable?(nil, Int(nBytes))
            }
        }
    }
    
    static let on_nf_write:nf_write_cb = { nfConn, status, ctx in
        guard let ctx = ctx, let owd = OnWriteData.fromContext(ctx) else {
            NSLog("ZitiConn on_nf_Write invalid ctx")
            return
        }
       
        // remove/clean-up regardless of whther or not error found
        if owd.mySelf.writeQueue.removeFirst() !== owd {
            NSLog("on_nf_write - WTF-OWD mismatch")
        }
        
        if status <= 0 {
            let errStr = String(cString: ziti_errorstr(Int32(status)))
            NSLog("ZitiConn on_nf_write, \(owd.mySelf.key), \(status):\"\(errStr)\"")
        } else if owd.len != status {
            NSLog("on_nf_write - WTF-LEN mismatch")
        }
        
        owd.ptr.deallocate()
        owd.mySelf.regulator?.decPending(owd.len)
    }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        //NSLog("ZitiConn connect \(key)")
        self.onDataAvailable = onDataAvailable
        
        // validate the service
        guard let svcName_c = svc.name?.cString(using: .utf8) else {
            NSLog("ZitiConn \(key) Unable to create C service name for \(zid.id):\(svc.name ?? "nil")")
            return false
        }
        
        zid.scheduleOp {
            // Is service avail (valid net session)?
            let availStatus = NF_service_available(self.zid.nf_context, svcName_c)
            if availStatus != ZITI_OK {
                let errStr = String(cString: ziti_errorstr(availStatus))
                NSLog("ZitiConn \(self.key) sevice avail = \"\(errStr)\"")
                self.onDataAvailable?(nil, Int(-1))
                return // false
            }
            
            // init the connection
            var status = NF_conn_init(self.zid.nf_context, &self.nfConn, self.toVoidPtr())
            guard status == ZITI_OK else {
                let errStr = String(cString: ziti_errorstr(status))
                NSLog("ZitiConn \(self.key) Unable to initiate connection for \(self.zid.id):\(self.svc.name ?? "nil"), \(errStr)")
                self.onDataAvailable?(nil, Int(-1))
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
        while !okToWrite && !connectFailed {
            writeCond.wait()
        }
        
        if connectFailed {
            writeCond.unlock()
            zid.scheduleOp { self.onDataAvailable?(nil, -1) }
        }
        writeCond.unlock()
        
        if payload.count <= 0 {
            NSLog("Ziti conn request to write \(payload.count) bytes \(key)")
            zid.scheduleOp { self.onDataAvailable?(nil, -1) }
        }
        
        // can't allow this to block curr thread or we can deadlock wating for wake signal
        //print("\(key) ziti write \(payload.count)")
        waitQueue.async {
            guard let regulator = self.regulator else {
                NSLog("No reguator for \(self.key)")
                return
            }
            
            if !regulator.wait(payload.count, 10.0) {
                NSLog("Ziti conn timed out waiting for ziti write window \(self.key)")
                self.zid.scheduleOp { self.onDataAvailable?(nil, -1) }
            } else {
                self.zid.scheduleOp {
                    guard self.closeWait == false else {
                        //print("closeWait drop write \(payload.count) bytes \(self.key)");
                        self.regulator?.decPending(payload.count)
                        return
                    }
                    
                    let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
                    ptr.initialize(from: [UInt8](payload), count: payload.count)
                    let owd = OnWriteData(ptr, payload.count, self)
                    self.writeQueue.append(owd)
                    let status = NF_write(self.nfConn, ptr, payload.count, ZitiConn.on_nf_write, owd.toVoidPtr())
                    
                    if status != ZITI_OK {
                        let errStr = String(cString: ziti_errorstr(status))
                        NSLog("ZitiConn \(self.key) Ignoring error writing \(payload.count) bytes. Code:\(status) Msg:\(errStr)")
                        return // -1
                    }
               }
            }
        }
        return payload.count // TODO: bogus
    }
    
    func close() {
        NSLog("ZitConn.close called, scheduleing close")
        zid.scheduleOp { [weak self] in
            if self?.closeWait ?? false {
                NSLog("ZitiConn releasing \(self?.key ?? "unk")")
                self?.releaseConnection?()
            } else if let mySelf = self, mySelf.nfConn != nil {
                NSLog("ZitiConn closing \(mySelf.key)")
                self?.closeWait = true
                let status = NF_close(&mySelf.nfConn)
                mySelf.nfConn = nil
                if status != ZITI_OK {
                    let errStr = String(cString: ziti_errorstr(status))
                    NSLog("ZitiConn.close error for \(mySelf.key), \(errStr)")
                }
            } else {
                NSLog("ZitiConn ignored, self: \(self != nil ? 1:0)")
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
