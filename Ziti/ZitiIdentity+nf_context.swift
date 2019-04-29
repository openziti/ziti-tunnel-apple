//
//  ZitiIdentity+nf_connection.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/28/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

fileprivate var nfContexts:[String:nf_context] = [:]

extension ZitiIdentity {
    
    func startRunloop() {
        let thread = Thread(target: self, selector: #selector(ZitiIdentity.doRunLoop), object: nil)
        thread.name = "\(id)_uv_runloop"
        thread.start()
    }
    
    var nf_context:nf_connection? { return nfContexts[id] }
    
    static let onNFInit:nf_init_cb = { nf_context, status, ctx in
        guard let mySelf = ZitiIdentity.fromContext(ctx) else {
            NSLog("ZitiIdentity.onNFInit WTF invalid ctx")
            return
        }
        print("onNFInit status: \(status), id: \(mySelf.id)")
        if status != ZITI_OK {
            NSLog("\(mySelf.id) onNFInit error: \(status)")
            NF_shutdown(nf_context)
            return
        }
        
        // save off nf_context
        nfContexts[mySelf.id] = nf_context
        
        // TODO: remove this...
        NF_dump(nf_context)
    }
    
    static let onUvTimer:uv_timer_cb = { th in
        guard let th = th, let mySelf = ZitiIdentity.fromContext(th.pointee.data) else {
            NSLog("ZitiIdentity.onUvTimer WTF invalid ctx")
            return
        }
        NSLog("\(mySelf.name):\(mySelf.id) runloop")
        
        /*
        if mySelf.thread?.isCancelled ?? true {
            NF_shutdown(mySelf.nfCtx)
            //NF_free(mySelf.nfCtx!)
            uv_timer_stop(th)
            uv_loop_close(mySelf.loop)
        }*/
    }
    
    @objc func doRunLoop() {
        var loop = uv_loop_t()
        
        // init the runloop
        if uv_loop_init(&loop) != 0 {
            NSLog("Unable to init runloop for \(name):\(id)")
            return
        }
        
        // init NF for this identity
        let zitiConfigPath_c = getCidPath() // keep swift refernece...
        if NF_init(zitiConfigPath_c, &loop, ZitiIdentity.onNFInit, self.toVoidPtr()) != 0 {
            NSLog("Unable to init SDK for \(name):\(id)")
            return
        }
        
        // setup keep-alive timer
        var th = uv_timer_t()
        guard uv_timer_init(&loop, &th) == 0 else {
            NSLog("zid(\(id)) unable to init runloop timer")
            return
        }
        th.data = self.toVoidPtr()
        
        let timeoutMs:UInt64 = 3 * 1000
        uv_timer_start(&th, ZitiIdentity.onUvTimer, timeoutMs, timeoutMs)
        
        // start the runloop
        NSLog("Starting runloop for \(name):\(id)")
        let runStatus = uv_run(&loop, UV_RUN_DEFAULT)
        NSLog("runloop exit status = \(runStatus) for \(name):\(id)")
        
        if uv_loop_close(&loop) != 0 {
            NSLog("Error closing runloop for \(name):\(id)")
        }
    }
    
    static func fromContext(_ ctx:Optional<UnsafeMutableRawPointer>) -> ZitiIdentity? {
        guard ctx != nil else { return nil }
        return Unmanaged<ZitiIdentity>.fromOpaque(UnsafeMutableRawPointer(ctx!)).takeUnretainedValue()
    }
    
    func toVoidPtr() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }
    
    func getCidPath() -> [CChar]? {
        var zitiConfigPath:String? = nil
        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ZitiIdentityStore.APP_GROUP_ID) {
            
            let url = appGroupURL.appendingPathComponent("\(id).cid", isDirectory:false)
            NSLog("cid path: \(url.path)")
            zitiConfigPath = url.path
        }
        return zitiConfigPath?.cString(using: .utf8)
    }
}
