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
    
    var thread:Thread?
    let writeCond = NSCondition()
    var okToWrite = false
    
    let zitiConfigPath_c:[CChar]?
    let loop:UnsafeMutablePointer<uv_loop_s>
    var nfCtx:nf_context?
    var nfConn:nf_connection?
        
    static func fromContext(_ ctx:Optional<UnsafeMutableRawPointer>) -> ZitiConn? {
        guard ctx != nil else { return nil }
        return Unmanaged<ZitiConn>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
    }
    
    func toVoidPtr() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService) {
        self.key = key
        self.zid = zid
        self.svc = svc
        self.loop = uv_default_loop()
        
        // get config path here so we keep a refernce to it...
        var zitiConfigPath:String? = nil
        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ZitiIdentityStore.APP_GROUP_ID) {
            
            let url = appGroupURL.appendingPathComponent("\(zid.id).cid", isDirectory:false)
            NSLog("cid path: \(url.path)")
            zitiConfigPath = url.path
        }
        
        // If this fails, C SDK will look in environment variable or HOME dir
        // (unlikely scenario, but possible...)
        zitiConfigPath_c = zitiConfigPath?.cString(using: .utf8)
        
        super.init()
        print("init ZitiConn \(key)")
    }
    
    deinit {
        print("deinit ZitiConn \(key)")
        close()
    }
    
    static let onNFInit:nf_init_cb = { nf_context, status, ctx in
        guard let mySelf = ZitiConn.fromContext(ctx) else {
            NSLog("ZitiConn.onNFInit WTF invalid ctx")
            return
        }
        print("onNFInit status: \(status), key: \(mySelf.key)")
        if status != ZITI_OK {
            NSLog("\(mySelf.key) onNFInit error: \(status)")
            NF_shutdown(nf_context)
            return
        }
        
        // Save for shutdown on thread cancel
        mySelf.nfCtx = nf_context
        
        // TODO: remove this...
        NF_dump(nf_context)
        
        // init the connection
        guard NF_conn_init(nf_context, &mySelf.nfConn, mySelf.toVoidPtr()) == ZITI_OK else {
            NSLog("ZitiConn \(mySelf.key) Unable to initiate connection for \(mySelf.zid.id):\(mySelf.svc.name ?? "nil")")
            NF_shutdown(nf_context)
            return
        }
        
        // validate the service
        guard let svcName_c = mySelf.svc.name?.cString(using: .utf8) else {
            NSLog("ZitiConn \(mySelf.key) Unable to create C service name for \(mySelf.zid.id):\(mySelf.svc.name ?? "nil")")
            NF_shutdown(nf_context)
            return
        }
        
        guard NF_service_available(nf_context, svcName_c) == ZITI_OK else {
            NSLog("ZitiConn \(mySelf.key) Service unavailable \(mySelf.zid.id):\(mySelf.svc.name ?? "nil")")
            NF_shutdown(nf_context)
            return
        }
        
        // dial it
        guard NF_dial(mySelf.nfConn, svcName_c, ZitiConn.onConn, ZitiConn.onData) == ZITI_OK else {
            NSLog("ZitiConn \(mySelf.key) Unable to dial service \(mySelf.zid.id):\(mySelf.svc.name ?? "nil")")
            NF_shutdown(nf_context)
            return
        }
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
        guard let mySelf = ZitiConn.fromContext(NF_conn_data(nfConn)) else {
            NSLog("ZitiConn.onData WTF invalid ctx")
            //NF_close(&nfConn)
            return
        }
        NSLog("ZitiConn.onData \(mySelf.key) \(nBytes) bytes")
        
        if nBytes > 0 && buf != nil {
            print("Calling onDataAvailable = \(mySelf.onDataAvailable != nil)")
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
        
        let status = NF_init(zitiConfigPath_c, loop, ZitiConn.onNFInit, self.toVoidPtr())
        if status == ZITI_OK {
            self.thread = Thread(target: self, selector: #selector(ZitiConn.doRunLoop), object: nil)
            thread?.name = key
            thread?.start()
        }
        return status == ZITI_OK
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
        
        // TODO: figure out how to avoid the copy (prob memoryRebound)
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        ptr.initialize(from: [UInt8](payload), count: payload.count)
        let status = NF_write(nfConn, ptr, payload.count)
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
            // NF_shutdown? thread safe?  Timer prob better...
        }
        if thread?.isCancelled ?? true == false { thread?.cancel() }
    }
    
    static let onUvTimer:uv_timer_cb = { th in
        guard let th = th, let mySelf = ZitiConn.fromContext(th.pointee.data) else {
            NSLog("ZitiConn.onUvTimer WTF invalid ctx")
            //NF_close(&nfConn)
            return
        }

        if mySelf.thread?.isCancelled ?? true {
            NSLog("Thread for \(mySelf.key) cancelled")
            mySelf.close()
            if mySelf.nfCtx != nil {
                NF_shutdown(mySelf.nfCtx)
                //NF_free(mySelf.nfCtx!)
                mySelf.nfCtx = nil // TODO: not right...
                uv_timer_stop(th)
                uv_loop_close(mySelf.loop)
            }
        }
    }
    
    @objc private func doRunLoop() {
        NSLog("Starting runloop \(key)")
        var th = uv_timer_t()
        guard uv_timer_init(loop, &th) == ZITI_OK else { // TODO: leak?
            NSLog("ZitiConn unable to init runloop timer")
            return
        }
        th.data = self.toVoidPtr()
        
        let timeoutMs:UInt64 = 3 * 1000
        uv_timer_start(&th, ZitiConn.onUvTimer, timeoutMs, timeoutMs)
        
        let runStatus = uv_run(loop, UV_RUN_DEFAULT)
        NSLog("runloop status = \(runStatus) for \(key)")
    }
}
