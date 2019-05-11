//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import tun2socks

class TcpRunloop: TSIPStackDelegate {
    
    let tunnelProvider:PacketTunnelProvider
    let dnsResolver:DNSResolver
    
    private var thread:Thread?
    private let queueLock = NSLock()
    private var rxQueue:[Data] = []
    private var txQueue:[(sock:TSTCPSocket?, data:Data?, len:Int)] = []
    
    private var tcpConns:[String:TCPSocketHandler] = [:]
    
    init(_ tp:PacketTunnelProvider, _ dnsR:DNSResolver) {
        tunnelProvider = tp
        dnsResolver = dnsR
        thread = Thread(target: self, selector: #selector(TcpRunloop.doRunLoop), object: nil)
        thread?.name = "TcpIp_runloop"
        thread?.start()
    }
    
    // Receive IP packet read from TUN
    func rcv(_ data:Data) {
        queueLock.lock()
        rxQueue.append(data)
        queueLock.unlock()
    }
    
    // Data to packetize and write to TUN
    func snd(_ sock:TSTCPSocket?, _ data:Data?, _ len:Int) {
        queueLock.lock()
        txQueue.append((sock:sock, data:data, len:len))
        queueLock.unlock()
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
            sock.close()
            return
        }
        
        // connect Ziti
        let zStarted = gotConn.connect { [weak self, weak sock] payload, nBytes in
            // queue for sending in run loop thread
            self?.snd(sock, payload, nBytes)
        }
        
        guard zStarted else {
            NSLog("Unable to start Ziti connection for \(key)")
            sock.close()
            return
        }
        
        // create delgate
        let delegate = TCPSocketHandler(gotConn)
        
        // keep delegate around until we know we're done with it (sock keeps a weak reference)
        tcpConns[key] = delegate
        delegate.release = {
            NSLog("Releasing \(key)")
            self.tcpConns.removeValue(forKey: key)
        }
        
        sock.delegate = delegate
    }
    
    // TSIPStack outputBlock (executes in run loop callback)
    func outputBlock(_ data:[Data], _ protocol:[NSNumber]) {
        data.forEach { pkt in
            //NSLog("tcp outputBlock - writing to packet flow..")
            tunnelProvider.writePacket(pkt)
        }
    }
    
    @objc func doRunLoop() {
        
        // This should be the first access (to create the stack on this thread)
        let tcpStack = TSIPStack.stack
        tcpStack.delegate = self
        tcpStack.outputBlock = self.outputBlock
        
        // Run forever...
        while !(thread?.isCancelled ?? true) {
            var rxRemaining = 0
            var rxData:Data?
            
            var txRemaining = 0
            var txData:(sock:TSTCPSocket?, data:Data?, len:Int)?
            
            queueLock.lock()
            if rxQueue.count > 0 {
                rxData = rxQueue.removeFirst()
                rxRemaining = rxQueue.count
            }
            if txQueue.count > 0 {
                txData = txQueue.removeFirst()
                txRemaining = txQueue.count
            }
            queueLock.unlock()
            
            // process inboud (from TUN)
            if rxData != nil {
                tcpStack.received(packet: rxData!)
            }
            
            // process outbound (to TUN through socket)
            if txData != nil {
                //NSLog("Ziti data avail, writing to \(txData!.data.count) bytes to sock")
                if let data = txData!.data, txData!.len > 0 {
                    txData!.sock?.writeData(data)
                } else {
                    NSLog("Received null payload or <= 0 nByes. nBytes=\(txData!.len). Closing sock")
                    txData!.sock?.close()
                    return
                }
                
            }
            
            // check timeouts (sys_check_timeouts())
            tcpStack.checkTimeout()
            
            // sleep for 250 milisecs if queues are empty
            if rxRemaining == 0 && txRemaining == 0 {
                Thread.sleep(forTimeInterval: TimeInterval(0.250))
            }
        }
    }
}
