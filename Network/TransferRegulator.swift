//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class TransferRegulator {
    let maxPending:Int
    var pending:Int = 0
    let cond = NSCondition()
    let name:String
    
    init(_ maxPending:Int, _ name:String) {
        self.maxPending = maxPending
        self.name = name
    }
    
    func decPending(_ by:Int) {
        cond.lock()
        pending -= by
        //print("   \(name) decPending by \(by). Now \(pending)")
        cond.signal()
        cond.unlock()
    }
    
    func wait(_ bytes:Int, _ ti:TimeInterval) -> Bool {
        var timedOut = false
        cond.lock()
        pending += bytes
        //print("   \(name) pending add \(bytes), now:\(pending), max: \(maxPending)")
        while pending > maxPending {
            if !cond.wait(until: Date(timeIntervalSinceNow: ti)) {
                NSLog("-- \(name) timed out waiting for other side to catch up")
                pending -= bytes
                timedOut = true
                break
            }
        }
        cond.unlock()
        return !timedOut
    }
}
