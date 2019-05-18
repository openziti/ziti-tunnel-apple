//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import tun2socks

class TcpRunloop: TSIPStackDelegate {
    
    let tcpStack = TSIPStack.stack
    let tunnelProvider:PacketTunnelProvider
    let dnsResolver:DNSResolver
    
    private var thread:Thread?
    private let opQueueLock = NSLock()
    private var opQueue:[(String?,()->Void)] = []
    
    private var tcpConns:[String:TCPSocketHandler] = [:]
    private var tcpConnsLock = NSLock()
    
    init(_ tp:PacketTunnelProvider, _ dnsR:DNSResolver) {
        tunnelProvider = tp
        dnsResolver = dnsR
        tcpStack.delegate = self
        tcpStack.outputBlock = self.outputBlock
        thread = Thread(target: self, selector: #selector(TcpRunloop.doRunLoop), object: nil)
        thread?.name = "TcpIp_runloop"
        thread?.start()
    }
    
    // schedule to run in run loop thread
    func scheduleOp(_ key:String?=nil, _ op: @escaping ()->Void) {
        tcpStack.dispatch_call {
            op()
         }
        /*****
        opQueueLock.lock()
        opQueue.append((key, op))
        opQueueLock.unlock()
 */
    }
    
    private func in_addrToString(_ inaddr:in_addr) -> String {
        let len   = Int(INET_ADDRSTRLEN) + 2
        var buf   = [CChar](repeating:0, count: len)
        
        var addrCopy = inaddr
        if let cs = inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(len)), let str = String(validatingUTF8: cs) {
            return str
        }
        return ""
    }
    
    // TSIPStackDelegate.  Executes in run loop thread
    func didAcceptTCPSocket(_ sock: TSTCPSocket) {
        let srcAddr = in_addrToString(sock.sourceAddress)
        let srcPort = sock.sourcePort
        let dstAddr = in_addrToString(sock.destinationAddress)
        let dstPort = sock.destinationPort
        
        let key = "TCP:\(srcAddr):\(srcPort)->\(dstAddr):\(dstPort)"
        NSLog("TCP Accepted \(key)")
        
        var zitiConn:ZitiClientProtocol? = nil
        
        // meant for Ziti?
        let intercept = "\(dstAddr):\(dstPort)"
        let (zidR, svcR) = tunnelProvider.getServiceForIntercept(intercept)
        if let zid = zidR, let svc = svcR {
            zitiConn = ZitiConn(key, zid, svc)
        } else {
            // if not for Ziti, can we proxy it to orginal IP address?
            let dnsRecs = dnsResolver.findRecordsByIp(dstAddr)
            for i in 0..<dnsRecs.count {
                if let realIp = dnsRecs[i].realIp {
                    zitiConn = TCPProxyConn(key, realIp, dstPort)
                    break
                }
            }
        }

        guard let gotConn = zitiConn else {
            NSLog("No Ziti connection available for \(key).  Closing...")
            //sock.close()
            return
        }
        
        // create delgate
        let delegate = TCPSocketHandler(gotConn)
        
        // keep delegate around until we know we're done with it (sock keeps a weak reference)
        tcpConnsLock.lock()
        tcpConns[key] = delegate
        tcpConnsLock.unlock()
        
        gotConn.releaseConnection = {
            NSLog("Releasing \(key)")
            self.tcpConnsLock.lock()
            self.tcpConns.removeValue(forKey: key)
            self.tcpConnsLock.unlock()
        }
        sock.delegate = delegate
        
        // connect Ziti
        let zStarted = gotConn.connect { [weak self, weak sock] payload, nBytes in
            // queue for sending in run loop thread
            if nBytes <= 0 || payload == nil {
                self?.scheduleOp {
                    print("Ziti done, closing sock (nBytes = \(nBytes), payload? == \(payload != nil))")
                    sock?.close()
                }
            } else {
                self?.scheduleOp(key) {
                    sock?.writeData(payload!)
                }
            }
        }
        
        guard zStarted else {
            NSLog("Unable to start Ziti connection for \(key)")
            sock.close()
            return
        }
    }
    
    // TSIPStack outputBlock (executes in run loop callback)
    func outputBlock(_ data:[Data], _ protocol:[NSNumber]) {
        data.forEach { pkt in
            //NSLog("tcp outputBlock - writing to packet flow..")
            tunnelProvider.writePacket(pkt)
        }
    }
    
    @objc func doRunLoop() {
        
        // Run forever...
        while !(thread?.isCancelled ?? true) {
            Thread.sleep(forTimeInterval: TimeInterval(0.250))
            tcpStack.dispatch_call { [weak self] in
                self?.tcpStack.checkTimeout()
            }
            
            /****
            // grab queue'd operations
            var currOps:[(String?, ()->Void)] = []
            opQueueLock.lock()
            while opQueue.count > 0 { currOps.append(opQueue.removeFirst()) }
            opQueueLock.unlock()
            
            // execure the ops
            while currOps.count > 0 {
                let (key, operation) = currOps.removeFirst()
                operation()
            }
            
            // check timeouts (sys_check_timeouts())
            tcpStack.checkTimeout()
            
            // sleep for a bit..
            Thread.sleep(forTimeInterval: TimeInterval(0.001))
 ****/
        }
    }
}
