//
//  TCPClientConn
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/19/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class TCPClientConn : NSObject {
    enum State : String {
        case LISTEN, SYN_RCVD, ESTABLISHED, CLOSE_WAIT, LAST_ACK, FIN_WAIT_1, FIN_WAIT_2, CLOSING, TIME_WAIT, Closed
    }
    var state:State = .LISTEN {
        willSet (newState) {
            NSLog("\(key) from \(state) to \(newState)")
        }
    }
    let key:String
    var zitiConn:ZitiClientProtocol?
    let mtu:Int
    
    var sourceAddr:Data = Data([0,0,0,0])
    var sourcePort:UInt16 = 0
    var destAddr:Data = Data([0,0,0,0])
    var destPort:UInt16 = 0
    
    var rcvWindow:UInt16 = 0
    var rcvWinScale:UInt8 = 0
    var rcvAckNum:UInt32 = 0
    var sendOldestUnAcked:UInt32 = 0 // UInt32.random(in: 0..<UInt32.max)
    var sendAckNum:UInt32 = 0
    let seqCond = NSCondition()
    
    typealias TCPSendCallback = ((TCPPacket?) -> Void)
    var onTCPSend:TCPSendCallback
    
    init(_ key:String, _ zitiConn:ZitiClientProtocol?, _ mtu:Int, onTCPSend:@escaping TCPSendCallback) {
        self.key = key
        self.zitiConn = zitiConn
        self.mtu = mtu
        self.onTCPSend = onTCPSend
        NSLog("TCPClientConn init \(key)")
    }
    
    deinit {
        NSLog("TCPClientConn deinit \(key)")
    }
    
    func tcpReceive(_ pkt:TCPPacket) -> TCPClientConn.State {
        
        //
        if pkt.RST {
            NSLog("\(key) RST received. Closing")
            zitiConn?.close()
            state = .Closed
            return state
        }
        
        //
        seqCond.lock()
        rcvWindow = pkt.windowSize
        if pkt.ACK {
            rcvAckNum = pkt.acknowledgmentNumber
            //NSLog("--- updated rcvAckNum: \(rcvAckNum) \(key)")
            seqCond.signal()
        }
        if pkt.SYN {
            (sendAckNum,_) = pkt.sequenceNumber.addingReportingOverflow(1) // +1 for syn received
        }
        if pkt.FIN {
            (sendAckNum,_) = sendAckNum.addingReportingOverflow(1)
        }
        
        switch state {
        case .LISTEN where pkt.SYN:
            sourceAddr = pkt.ip.sourceAddress
            sourcePort = pkt.sourcePort
            destAddr = pkt.ip.destinationAddress
            destPort = pkt.destinationPort
            rcvWinScale = parseWinScale(pkt.options)
            sendOldestUnAcked = UInt32.random(in: 0..<UInt32.max)
            
            if zitiConn == nil {
                NSLog("No connection available for \(key)")
                state = .Closed
                tcpSend(nil, TCPFlags.ACK.rawValue|TCPFlags.RST.rawValue)
            } else {
            
                state = .SYN_RCVD
                let mss = mtu - Int(IPv4Packet.minHeaderBytes + TCPPacket.minHeaderBytes)
                let zsStarted = zitiConn?.connect { [weak self] payload, nBytes in
                    //NSLog("Read \(nBytes) from Ziti, Thread \(Thread.current)")
                    let key = self?.key ?? "<no-key>"
                    if nBytes <= 0 {
                        // 0 = eo-buffer
                        NSLog("\(key) Ziti-side read close or error.  Sending FIN/ACK ")
                        
                        self?.seqCond.lock()
                        // TODO: figure this close sequence out so its consistant...
                        self?.tcpSend(nil, TCPFlags.FIN.rawValue|TCPFlags.ACK.rawValue) // doesn't always work (e.g., iperf only if we onTCPSend(nil) - bad idea from this thread (ziti reads happens in their own thread)
                        self?.zitiConn?.close()
                        self?.seqCond.unlock()
     
                    } else {
                        let n = nBytes
                        var i = 0
                        var chunkLen:Int
                        while i < n {
                            if i + mss > n {
                                chunkLen = n % mss
                            } else {
                                chunkLen = mss
                            }
                            let chunk = payload!.subdata(in: i..<(i+chunkLen))
                            self?.seqCond.lock()
                            if !(self?.waitForClientAcks(count: UInt32(nBytes)) ?? false) {
                                NSLog("xxxxxxx \(key) Failed waiting for client ACKs.  TODO...")
                            }
                            self?.tcpSend(chunk, TCPFlags.ACK.rawValue)
                            //NSLog("   sent \(i+chunk.count) of \(n) bytes")
                            self?.seqCond.unlock()
                            i += mss
                        }
                    }
                }
                if zsStarted ?? false == false {
                    NSLog("Unable to start Ziti for connection \(key)")
                    state = .Closed
                    tcpSend(nil, TCPFlags.ACK.rawValue|TCPFlags.RST.rawValue)
                } else {
                    tcpSend(nil, TCPFlags.SYN.rawValue|TCPFlags.ACK.rawValue, makeSynOpts())
                }
            }
        case .SYN_RCVD where pkt.RST:
            state = .LISTEN
        case .SYN_RCVD where pkt.ACK:
            state = .ESTABLISHED
        case .ESTABLISHED:
            if pkt.FIN {
                // Connection terminated by local application
                state = .CLOSE_WAIT
                tcpSend(nil, TCPFlags.ACK.rawValue)
            } else {
                // Data Transfer
                let count = UInt32(pkt.payload?.count ?? 0)
                if count > 0 {
                    (sendAckNum,_) = sendAckNum.addingReportingOverflow(count)
                    tcpSend(nil, TCPFlags.ACK.rawValue)
                    //NSLog("\(key) ACKd \(count) bytes, sendAckNum=\(sendAckNum)")
                    seqCond.unlock()
                    if zitiConn?.write(payload: pkt.payload!) ?? -1 == -1 {
                        NSLog("\(key) Unable to write \(count) bytes")
                        onTCPSend(nil)
                    }
                    return state
                }
            }
        case .LAST_ACK where pkt.ACK:
            state = .Closed
        case .FIN_WAIT_1: // Connection terminated by Ziti
            if pkt.FIN && pkt.ACK {
                state = .TIME_WAIT
                tcpSend(nil, TCPFlags.ACK.rawValue)
            } else if pkt.FIN {
                state = .CLOSING
                tcpSend(nil, TCPFlags.ACK.rawValue)
            } else if pkt.ACK {
                state = .FIN_WAIT_2
            }
        case .FIN_WAIT_2 where pkt.FIN:
            state = .TIME_WAIT
            tcpSend(nil, TCPFlags.ACK.rawValue)
        case .CLOSING where pkt.ACK:
            state = .TIME_WAIT
        case .TIME_WAIT where pkt.FIN:
            tcpSend(nil, TCPFlags.ACK.rawValue)
        default:
            NSLog("\(key) Unexpected TCP state transistion for \(key). State=\(state)")
            zitiConn?.close()
            onTCPSend(nil)
        }
        
        if state == .Closed {
            NSLog("\(key) Received packet on closed session")
            zitiConn?.close()
            onTCPSend(nil)
        } else if state == .CLOSING {
            NSLog("\(key) closing")
        } else if state == .CLOSE_WAIT {
            state = .LAST_ACK
            tcpSend(nil, TCPFlags.FIN.rawValue | TCPFlags.ACK.rawValue) // added ACK
            zitiConn?.close()
            onTCPSend(nil)
        }
        seqCond.unlock()
        return state
    }
    
    func tcpSend(_ payload:Data?, _ flags:UInt8, _ options:[TCPOption]?=nil) {
        guard let ipPkt = IPv4Packet(count: IPv4Packet.minHeaderBytes + TCPPacket.minHeaderBytes) else {
            return
        }
        
        let pkt = TCPPacket(ipPkt, options:options, payload:payload)
        pkt?.ip.sourceAddress = destAddr
        pkt?.sourcePort = destPort
        pkt?.ip.destinationAddress = sourceAddr
        pkt?.destinationPort = sourcePort
        
        var ackNum = UInt32(0)
        if flags & TCPFlags.ACK.rawValue != 0 {
            ackNum = sendAckNum
        }
        let (seqNum,_) = sendOldestUnAcked.addingReportingOverflow(1)
        
        pkt?.sequenceNumber = seqNum
        pkt?.acknowledgmentNumber = ackNum
        pkt?.windowSize = 0xffff
        pkt?.flags = flags
        pkt?.updateLengthsAndChecksums()
        
        var inc = UInt32(payload?.count ?? 0)
        if pkt?.SYN ?? false || pkt?.FIN ?? false {
            (inc,_) = inc.addingReportingOverflow(1)
        }
        (sendOldestUnAcked,_) = sendOldestUnAcked.addingReportingOverflow(inc)
        
        onTCPSend(pkt)
    }
    
    override var debugDescription: String {
        return "\(key) \(state)"
    }
    
    // check peer's receive window and wait for it to open if necessary
    private func waitForClientAcks(count:UInt32) -> Bool {
        
        //NSLog("xxxxxxx WFCA oldest unAck=\(sendOldestUnAcked), last rcvAck=\(rcvAckNum), diff=\(Int(rcvAckNum)-Int(sendOldestUnAcked)) winXscale=\((Int(rcvWindow) << rcvWinScale))")
        while ((Int(sendOldestUnAcked) + Int(count)) - Int(rcvAckNum)) > (Int(rcvWindow) << rcvWinScale) {
            if rcvWindow == 0 {
                NSLog("xxxxxxxx \(key) Window closed.")
                return true //?
            }
            NSLog("xxxxxxxx \(key) Waiting for client to ACK byte \(sendOldestUnAcked)")
            if !seqCond.wait(until: Date(timeIntervalSinceNow: TimeInterval(5.0))) {
                NSLog("xxxxxxxx \(key) Timed-out waiting for client to ACK byte \(sendOldestUnAcked)")
                return false
            }
            NSLog("xxxxxxxx \(key) Done waiting for client to ACK byte \(sendOldestUnAcked)")
        }
        return true
    }
    
    private func parseWinScale(_ options:TCPOptions?) -> UInt8 {
        guard let options = options else { return 1 }
        for opt in options.options {
            if let wsOpt = opt as? TCPOptionWindowScale {
                return wsOpt.scale
            }
        }
        return 0
    }
    
    private func makeSynOpts() -> [TCPOption] {
        var options:[TCPOption] = []
        let mss:UInt16 = UInt16(mtu) - UInt16(IPv4Packet.minHeaderBytes + TCPPacket.minHeaderBytes)
        if let mssOpt = TCPOptionMss(mss) { options.append(mssOpt) }
        if let nop = TCPOption(Data([TCPOptionKind.nop.rawValue])) { options.append(nop) }
        if let ws = TCPOptionWindowScale(0x07) { options.append(ws) }
        return options
    }
}
