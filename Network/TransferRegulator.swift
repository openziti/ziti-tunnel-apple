//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class TransferRegulator {
    let maxPending:Int
    var pending:Int = 0
    let cond = NSCondition()
    
    init(_ maxPending:Int) {
        self.maxPending = maxPending
    }
    
    func decPending(_ by:Int) {
        cond.lock()
        pending -= by
        cond.signal()
        cond.unlock()
    }
    
    func wait(_ bytes:Int, _ ti:TimeInterval) -> Bool {
        var timedOut = false
        cond.lock()
        pending += bytes
        while pending > maxPending {
            if !cond.wait(until: Date(timeIntervalSinceNow: ti)) {
                NSLog("-- TransferRegulator timed out waiting for other side to catch up")
                pending -= bytes
                timedOut = true
                break
            }
        }
        cond.unlock()
        return !timedOut
    }
}
