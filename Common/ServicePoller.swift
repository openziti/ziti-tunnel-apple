//
//  ServicePoller.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/13/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ServicePoller : NSObject {
    weak var zidMgr:ZidMgr?
    var timer:Timer? = nil
    typealias OnServicePoll = (Bool, ZitiIdentity) -> Void
    var timeInterval = TimeInterval(15.0)
    var onServicePoll:OnServicePoll? = nil
    
    func pollOnce() {
        zidMgr?.zids.forEach { zid in
            if (zid.enrolled ?? false) == true && (zid.enabled ?? false) == true {
                zid.edge.getServices { [weak self] didChange, _ in
                    self?.onServicePoll?(didChange, zid)
                }
            } else {
                onServicePoll?(false, zid)
            }
        }
    }
    
    func startPolling(_ onServicePoll:OnServicePoll?=nil) {
        if onServicePoll != nil {
            self.onServicePoll = onServicePoll
        }
        
        if timer?.isValid ?? false { timer?.invalidate() }
        pollOnce()
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }
    
    func stopPolling() { timer?.invalidate() }
    deinit { timer?.invalidate() }
}
