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
        print("init ZitiConn \(key)")
    }
    
    deinit {
        print("deinit ZitiConn \(key)")
        close()
    }
    
    static let onConn:nf_conn_cb = { nfConn, status in
        guard let mySelf = ZitiConn.fromContext(NF_conn_data(nfConn)) else {
            NSLog("ZitiConn.onConn WTF invalid ctx")
            //NF_close(&nfConn)
            return
        }
        print("ZitiConn.onConn OK to write \(mySelf.key)")
        mySelf.okToWrite = true
        mySelf.writeCond.signal()
    }
    
    static let onData:nf_data_cb = { nfConn, buf, nBytes in
        guard nBytes > 0 && buf != nil else {
            // TODO: why sometimes to -6 and nil here? (after closing connection)
            NSLog("ZitiConn.onData Unexpected data received, len=\(nBytes), bufPtr=\(buf != nil)")
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
            // delgate calls close() when this happens (TODO: prob want to change that, esp if I need to NF_shutdown)
            mySelf.onDataAvailable?(nil, Int(nBytes))
        }
    }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        NSLog("ZitiConn connect \(key)")
        self.onDataAvailable = onDataAvailable
        
        // init the connection
        guard NF_conn_init(zid.nf_context, &nfConn, self.toVoidPtr()) == ZITI_OK else {
            NSLog("ZitiConn \(key) Unable to initiate connection for \(zid.id):\(svc.name ?? "nil")")
            NF_shutdown(zid.nf_context)
            return false
        }
                
        // validate the service
        guard let svcName_c = svc.name?.cString(using: .utf8) else {
            NSLog("ZitiConn \(key) Unable to create C service name for \(zid.id):\(svc.name ?? "nil")")
            NF_shutdown(zid.nf_context)
            return false
        }
        
        guard NF_service_available(zid.nf_context, svcName_c) == ZITI_OK else {
            NSLog("ZitiConn \(key) Service unavailable \(zid.id):\(svc.name ?? "nil")")
            NF_shutdown(zid.nf_context)
            return false
        }
        
        // dial it
        guard NF_dial(nfConn, svcName_c, ZitiConn.onConn, ZitiConn.onData) == ZITI_OK else {
            NSLog("ZitiConn \(key) Unable to dial service \(zid.id):\(svc.name ?? "nil")")
            NF_shutdown(zid.nf_context)
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
            NSLog("ZitiConn \(key) Error writing, status=\(status)")
            return -1
        }
        return payload.count
    }
    
    func close() {
        NSLog("ZitiConn close \(key)")
        if nfConn != nil {
            if NF_close(&nfConn) != ZITI_OK {
                NSLog("ZitiConn.close error for \(key)")
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
