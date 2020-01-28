//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import Network
import tun2socks

class TcpRunloop: TSIPStackDelegate {
    
    let tcpStack = TSIPStack.stack
    let tunnelProvider:PacketTunnelProvider
    let netMon = NWPathMonitor()
    var currPath:NWPath?
    let dnsResolver:DNSResolver
    let socketRegulator = TransferRegulator(Int(0xffff), "SockRegulator") // TODO = TCP_SND_BUF
    let zitiRegulator = TransferRegulator(Int(0xffff), "ZitiRegulator")
    let waitQueue = DispatchQueue(label: "TcpWaitQueue", attributes: [])
    
    //private var thread:Thread?
    //private let opQueueLock = NSLock()
    //private var opQueue:[(String?,()->Void)] = []
    
    private var tcpConns:[String:TCPSocketHandler] = [:]
    private var tcpConnsLock = NSLock()
    
    init(_ tp:PacketTunnelProvider, _ dnsR:DNSResolver) {
        tunnelProvider = tp
        dnsResolver = dnsR
        tcpStack.delegate = self
        tcpStack.outputBlock = self.outputBlock
        netMon.pathUpdateHandler = self.pathUpdateHandler
        netMon.start(queue: tcpStack.processQueue)
        
        //thread = Thread(target: self, selector: #selector(TcpRunloop.doRunLoop), object: nil)
        //thread?.name = "TcpIp_runloop"
        //thread?.start()
    }
    
    // schedule to run in run loop thread
    func scheduleOp(_ key:String?=nil, _ op: @escaping ()->Void) {
        tcpStack.dispatch_call { op() }
        /*******
        opQueueLock.lock()
        opQueue.append((key, op))
        opQueueLock.unlock()
 *******/
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
        var zitiConn:ZitiClientProtocol? = nil
        
        let key = "TCP:\(srcAddr):\(srcPort)->\(dstAddr):\(dstPort)"
        guard currPath?.status ?? .unsatisfied != .unsatisfied else {
            NSLog("No network path avaialble for \(key). Closing...")
            sock.close()
            return
        }
        
        // meant for Ziti?
        let intercept = "\(dstAddr):\(dstPort)"
        let (zidR, svcR) = tunnelProvider.getServiceForIntercept(intercept)
        if let zid = zidR, let svc = svcR {
            zitiConn = ZitiConn(key, zid, svc, zitiRegulator)
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
        
        NSLog("TCP Accepted \(key)")
        let delegate = TCPSocketHandler(gotConn, socketRegulator)
        
        // keep delegate around until we know we're done with it (sock keeps a weak reference)
        tcpConnsLock.lock()
        tcpConns[key] = delegate
        tcpConnsLock.unlock()
        
        gotConn.releaseConnection = {
            self.tcpConnsLock.lock()
            NSLog("TCP Releasing \(key)")
            self.tcpConns.removeValue(forKey: key)
            self.tcpConnsLock.unlock()
        }
        sock.delegate = delegate
        
        // connect Ziti
        let zStarted = gotConn.connect { [weak self, weak sock] payload, nBytes in
            // queue for sending in run loop thread
            if nBytes <= 0 || payload == nil {
                self?.scheduleOp {
                    //print("   ... (done) closing sock \(key) isConnected? \(sock?.isConnected ?? false), nBytes:\(nBytes)")
                    //print("   ... delegate? \((sock?.delegate != nil) ? "yes" : "no")")
                    //print("   ... sock? \((sock?.delegate != nil) ? "yes" : "no")")
                    sock?.close()
                }
            } else {
                // need to get the wait() onto a diff thread.
                // (its executing on the ziti run loop, which could block waiting for a signal from this run look)
                self?.waitQueue.async {
                    if !(self?.socketRegulator.wait(payload!.count, 5.0) ?? false) { //PIG
                        NSLog("TCP ziti conn timed out waiting for socket write window \(key)")
                        //print("   ... self? \(self == nil ? "nope" : "yep")")
                        self?.scheduleOp {
                            //print("   ... (regulator) closing sock \(key)")
                            sock?.close()
                            
                            // PIG: could dec more than it should.  move this to socket delegate and maintain counter...
                            self?.socketRegulator.decPending(self?.socketRegulator.pending ?? 0)
                            //
                        }
                    } else {
                        self?.scheduleOp(key) {
                            if sock?.isConnected ?? false {
                                //print("\(key) socket write \(payload!.count)")
                                sock?.writeData(payload!)
                            } else {
                                self?.socketRegulator.decPending(payload!.count)
                            }
                        }
                    }
                }
            }
        }
        
        guard zStarted else {
            NSLog("Unable to start Ziti connection for \(key)")
            sock.close()
            return
        }
    }
    
    // TSIPStack outputBlock (executes in tcpStack's processQueue)
    func outputBlock(_ data:[Data], _ protocol:[NSNumber]) {
        data.forEach { pkt in
            //NSLog("tcp outputBlock - writing to packet flow..")
            tunnelProvider.writePacket(pkt)
        }
    }
    
    // netMon callback, runs in tcpStack's processQueue
    func pathUpdateHandler(path: Network.NWPath) {
        currPath = path
        
        var ifaceStr = ""
        for i in path.availableInterfaces {
            ifaceStr += " \n     \(i.index): name:\(i.name), type:\(i.type)"
        }
        NSLog("Network Path Update:\n   Status:\(path.status), Expensive:\(path.isExpensive), Cellular:\(path.usesInterfaceType(.cellular))\n   Interfaces:\(ifaceStr)")
    }
    
/*
    @objc func doRunLoop() {
        
        // Run forever...
        while !(thread?.isCancelled ?? true) {
            Thread.sleep(forTimeInterval: TimeInterval(0.250))
            
            /* Needed? */
            tcpStack.dispatch_call { [weak self] in
                self?.tcpStack.checkTimeout()
            }
            
            /******
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
 **********/
        }
    }
 */
}
