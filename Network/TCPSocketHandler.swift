//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import tun2socks

class TCPSocketHandler: TSTCPSocketDelegate {
    var ziti:ZitiClientProtocol
    
    init(_ ziti:ZitiClientProtocol) {
        self.ziti = ziti
        NSLog("TCPSocketHandler init")
    }
    
    deinit {
        NSLog("TCPSocketHandler deinit")
    }
    
    func localDidClose(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler localDidClose. Closing Ziti")
        ziti.close()
    }
    
    func socketDidReset(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidReset. Closing Ziti")
        ziti.close()
    }
    
    func socketDidAbort(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidAbort. Closing Ziti")
        ziti.close()
    }
    
    func socketDidClose(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidClose. Closing Ziti")
        ziti.close()
    }
    
    func didReadData(_ data: Data, from: TSTCPSocket) {
        _ = ziti.write(payload: data)
    }
    
    func didWriteData(_ length: Int, from: TSTCPSocket) {
        //NSLog("TCPSocketHandler didWriteData: \(length) bytes were written (back to TUN)")
    }
}
