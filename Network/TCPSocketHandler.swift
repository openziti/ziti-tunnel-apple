//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import tun2socks

class TCPSocketHandler: TSTCPSocketDelegate {
    var ziti:ZitiClientProtocol
    
    var release:(()->Void)?
    
    init(_ ziti:ZitiClientProtocol) {
        self.ziti = ziti
        NSLog("TCPSocketHandler init")
    }
    
    deinit {
        NSLog("TCPSocketHandler deinit")
    }
    
    func localDidClose(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler localDidClose. Closing Ziti and releasing delegate")
        ziti.close()
        release?()
    }
    
    func socketDidReset(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidReset. Close ziti and release delegate")
        ziti.close() // not sure
        release?()
    }
    
    func socketDidAbort(_ socket: TSTCPSocket) {
        ziti.close() // not sure
        release?()
    }
    
    func socketDidClose(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidClose. Releasing delegate")
        // Ziti closes, should be all done
        release?()
    }
    
    func didReadData(_ data: Data, from: TSTCPSocket) {
        NSLog("TCPSocketHandler didReadData: \(data.count) byes read and available.  Sending to Ziti")
        let len = ziti.write(payload: data)
        NSLog("   ...wrote \(len) to Ziti")
    }
    
    func didWriteData(_ length: Int, from: TSTCPSocket) {
        NSLog("TCPSocketHandler didWriteData: \(length) bytes were written (back to TUN)")
    }
    
    
}
