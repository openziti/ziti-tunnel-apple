//
//  ZitiConn.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/7/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiConn : NSObject, ZitiClientProtocol {
    var onDataAvailable:DataAvailableCallback?
    
    let key:String
    let zid:ZitiIdentity
    let svc:ZitiEdgeService
    
    let writeCond = NSCondition()
    var okToWrite = false
    
    var nfConn:nf_connection?
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService) {
        self.key = key
        self.zid = zid
        self.svc = svc
        
        super.init()
        NSLog("init ZitiConn \(key)")
    }
    
    deinit {
        NSLog("deinit ZitiConn \(key)")
        close()
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
        guard nBytes > 0 && buf != nil else {
            let errStr = String(cString: ziti_errorstr(nBytes))
            NSLog("ZitiConn.onData closing: \(errStr)")
            return
        }
        guard let nfConn = nfConn, let mySelf = ZitiConn.fromContext(NF_conn_data(nfConn)) else {
            NSLog("ZitiConn.onData WTF invalid ctx")
            return
        }
        NSLog("ZitiConn.onData \(mySelf.key) \(nBytes) bytes")
        
        if nBytes > 0 && buf != nil {
            let data = Data(bytesNoCopy: buf!, count: Int(nBytes), deallocator: .none)
            mySelf.onDataAvailable?(data, Int(nBytes))
        } else {
            // 0 == eob, -1 == error.
            // delgate calls close() when this happens
            mySelf.onDataAvailable?(nil, Int(nBytes))
        }
    }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        NSLog("ZitiConn connect \(key)")
        self.onDataAvailable = onDataAvailable
        
        // init the connection
        var status = NF_conn_init(zid.nf_context, &nfConn, self.toVoidPtr())
        guard  status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            NSLog("ZitiConn \(key) Unable to initiate connection for \(zid.id):\(svc.name ?? "nil"), \(errStr)")
            return false
        }

        // validate the service
        guard let svcName_c = svc.name?.cString(using: .utf8) else {
            NSLog("ZitiConn \(key) Unable to create C service name for \(zid.id):\(svc.name ?? "nil")")
            return false
        }
        
        // dial it
        status = NF_dial(nfConn, svcName_c, ZitiConn.on_nf_conn, ZitiConn.on_nf_data)
        guard  status == ZITI_OK else {
            let errStr = String(cString: ziti_errorstr(status))
            NSLog("ZitiConn \(key) Unable to dial service \(zid.id):\(svc.name ?? "nil"), \(errStr)")
            return false
        }
        
        return true
    }
    
    func write(payload:Data) -> Int {
        print("ZitiConn attempt to write \(payload.count) bytes")
        writeCond.lock()
        while !okToWrite {
            if !writeCond.wait(until: Date(timeIntervalSinceNow: 3.0)) { // TODO: ridic timeout...
                NSLog("*** ZitiConn \(key) timed out waiting for ziti connection callback")
                writeCond.unlock()
                return -1
            }
        }
        
        // TODO: figure out how to avoid the copy (making payload optional would help)
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        ptr.initialize(from: [UInt8](payload), count: payload.count)
        let status = NF_write(nfConn, ptr, payload.count)
        ptr.deallocate()
        writeCond.unlock()
        
        if status != ZITI_OK {
            let errStr = String(cString: ziti_errorstr(status))
            NSLog("ZitiConn \(key) Error writing: \(errStr)")
            return -1
        }
        return payload.count
    }
    
    func close() {
        NSLog("ZitiConn close \(key)")
        if nfConn != nil {
            let status = NF_close(&nfConn)
            if status != ZITI_OK {
                let errStr = String(cString: ziti_errorstr(status))
                NSLog("ZitiConn.close error for \(key), \(errStr)")
            }
            nfConn = nil
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
