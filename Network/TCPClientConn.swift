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
    let zid:ZitiIdentity
    let svc:ZitiEdgeService
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
    
    weak var ptp:PacketTunnelProvider!
    var ziti:ZitiClientProtocol? = nil
    
    typealias TCPSendCallback = ((TCPPacket?) -> Void)
    var onTCPSend:TCPSendCallback
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService, _ ptp:PacketTunnelProvider, onTCPSend:@escaping TCPSendCallback) {
        self.key = key
        self.zid = zid
        self.svc = svc
        self.ptp = ptp
        self.mtu = ptp.providerConfig.mtu
        self.onTCPSend = onTCPSend
        NSLog("init \(key)")
    }
    
    deinit {
        NSLog("deinit \(key)")
    }
    
    func tcpReceive(_ pkt:TCPPacket) -> TCPClientConn.State {
        seqCond.lock()
        rcvWindow = pkt.windowSize
        if pkt.ACK {
            rcvAckNum = pkt.acknowledgmentNumber
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
            state = .SYN_RCVD
            let mss = mtu - Int(IPv4Packet.minHeaderBytes + TCPPacket.minHeaderBytes)
            ziti = TCPProxyConn(mss:mss)
            let zsStarted = ziti?.start { [weak self] payload, nBytes in
                //NSLog("Read \(nBytes) from Ziti, Thread \(Thread.current)")
                if nBytes <= 0 {
                    // 0 = eo-buffer
                    NSLog("Ziti-side server close or error.  Sending FIN/ACK ")
                    
                    // TODO: should go someplace else first to figure out window scale...
                    self?.seqCond.lock()
                    self?.tcpSend(nil, TCPFlags.FIN.rawValue|TCPFlags.ACK.rawValue)
                    self?.seqCond.unlock()
                } else {
                    // TODO: should go someplace else first to figure out window scale...
                    self?.seqCond.lock()
                    self?.tcpSend(payload, TCPFlags.ACK.rawValue)
                    self?.seqCond.unlock()
                }
            }
            if zsStarted ?? false == false {
                NSLog("Unable to start Ziti for connection \(key)")
                onTCPSend(nil)
                seqCond.unlock()
                state = .Closed
                return state
            }
            sourceAddr = pkt.ip.sourceAddress
            sourcePort = pkt.sourcePort
            destAddr = pkt.ip.destinationAddress
            destPort = pkt.destinationPort
            rcvWinScale = parseWinScale(pkt.options)
            sendOldestUnAcked = UInt32.random(in: 0..<UInt32.max)
            tcpSend(nil, TCPFlags.SYN.rawValue|TCPFlags.ACK.rawValue, makeSynOpts())
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
                    (sendAckNum,_) = sendAckNum.addingReportingOverflow(count)  // todo: check on slices
                    tcpSend(nil, TCPFlags.ACK.rawValue)
                    seqCond.unlock()
                    if ziti?.write(payload: pkt.payload!) ?? -1 == -1 {
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
            ziti?.close()
            onTCPSend(nil)
        }
        
        if state == .Closed {
            NSLog("\(key) Received packet on closed session")
            ziti?.close()
            onTCPSend(nil)
        } else if state == .CLOSING {
            NSLog("\(key) closing")
        } else if state == .CLOSE_WAIT {
            state = .LAST_ACK
            tcpSend(nil, TCPFlags.FIN.rawValue | TCPFlags.ACK.rawValue) // added ACK
            ziti?.close()
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
