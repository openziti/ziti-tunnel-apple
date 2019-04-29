//
//  ZitiIdentity+nf_connection.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/28/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

extension ZitiIdentity {
    var nf_context_key:String { return "\(id)_nf_context" }
    var nf_init_cond_key:String { return "nf_init_cond" }
    
    var nf_context:nf_context? { return Thread.main.threadDictionary[nf_context_key] as? nf_context }
    var nf_init_cond:NSCondition? { return Thread.current.threadDictionary[nf_init_cond_key] as? NSCondition }
    
    func startRunloop(_ blocking:Bool=true) {
        let thread = Thread(target: self, selector: #selector(ZitiIdentity.doRunLoop), object: nil)
        thread.name = "\(id)_uv_runloop"
        let cond = blocking ? NSCondition() : nil
        thread.threadDictionary[nf_init_cond_key] = cond
        thread.start()
        
        nf_init_cond?.lock()
        while blocking && nf_context == nil {
            let ti = TimeInterval(10.0) // give it 10 seconds (should be done in < 1/2 of that)
            NSLog("\(name):\(id) Waiting \(ti) for SDK on_nf_init()..")
            if let cond = cond, !cond.wait(until: Date(timeIntervalSinceNow: ti))  {
                NSLog("** \(name):\(id) timed out waiting for on_nf_init()")
            }
        }
        NSLog("\(name):\(id) Done waiting for SDK on_nf_init()...")
        nf_init_cond?.unlock()
    }
    
    static let on_nf_init:nf_init_cb = { nf_context, status, ctx in
        guard let mySelf = ZitiIdentity.fromContext(ctx) else {
            NSLog("ZitiIdentity on_nf_init WTF invalid ctx")
            return
        }
        print("on_nf_init status: \(status), id: \(mySelf.id)")
        if status != ZITI_OK {
            NSLog("\(mySelf.id) onNFInit error: \(status)")
            NF_shutdown(nf_context)
            return
        }
        
        // save off nf_context
        Thread.main.threadDictionary[mySelf.nf_context_key] = nf_context
        
        // TODO: remove this...
        NF_dump(nf_context)
        
        // signal init condition
        mySelf.nf_init_cond?.signal()
    }
    
    static let on_uv_timer:uv_timer_cb = { th in
        guard let th = th, let mySelf = ZitiIdentity.fromContext(th.pointee.data) else {
            NSLog("ZitiIdentity.onUvTimer WTF invalid ctx")
            return
        }
        NSLog("\(mySelf.name):\(mySelf.id) runloop alive")
        
        //
        // Could uv_timer_stop(tv), NF_shutdown(mySelf.nf_context) based on
        // (atomic) Bool or somesuch.  But zids live for lifetime of tunnel,
        // and tunnel currently does exit(0), not a need right now
        //
    }
    
    @objc func doRunLoop() {
        print("RunLoop thread = \(Thread.current)")
        var loop = uv_loop_t()
        
        // init the runloop
        if uv_loop_init(&loop) != 0 {
            NSLog("Unable to init runloop for \(name):\(id)")
            return
        }
        
        // init NF for this identity
        let zitiConfigPath_c = getCidPath() // keep swift refernece...
        if NF_init(zitiConfigPath_c, &loop, ZitiIdentity.on_nf_init, self.toVoidPtr()) != 0 {
            NSLog("Unable to init SDK for \(name):\(id)")
            return
        }
        
        // setup keep-alive timer (else uv_run immediately exits since nothing gets confired
        // on the loop until we receive a client connection
        var th = uv_timer_t()
        guard uv_timer_init(&loop, &th) == 0 else {
            NSLog("zid(\(id)) unable to init runloop timer")
            return
        }
        th.data = self.toVoidPtr()
        
        let timeoutMs:UInt64 = 300 * 1000 // 5 mins for now since we don't do anything useful in the callback
        uv_timer_start(&th, ZitiIdentity.on_uv_timer, timeoutMs, timeoutMs)
        
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
