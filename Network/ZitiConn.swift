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
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService) {
        self.key = key
        self.zid = zid
        self.svc = svc
        NSLog("init ZitiConn")
    }
    
    deinit {
        NSLog("deinit ZitiConn")
        close()
    }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool {
        NSLog("ZitiConn connect TODO")
        return false
    }
    
    func write(payload:Data) -> Int {
        NSLog("ZitiConn write TODO")
        return -1
    }
    
    func close() {
        NSLog("ZitiConn close TODO")
    }
}
