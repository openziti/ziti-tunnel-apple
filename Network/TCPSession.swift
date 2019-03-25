//
//  TCPSession.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/19/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class TCPSession : NSObject {
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
    
    typealias TCPSendCallback = ((TCPPacket?) -> Void)
    var onTCPSend:TCPSendCallback
    
    init(_ key:String, _ zid:ZitiIdentity, _ svc:ZitiEdgeService, _ mtu:Int, onTCPSend:@escaping TCPSendCallback) {
        self.key = key
        self.zid = zid
        self.svc = svc
        self.mtu = mtu
        self.onTCPSend = onTCPSend
        NSLog("init \(key)")
    }
    
    deinit {
        NSLog("deinit \(key)")
    }
    
    func tcpReceive(_ pkt:TCPPacket) -> TCPSession.State {
        // seqCond.lock()
        rcvWindow = pkt.windowSize
        if pkt.hasFlags(TCPFlags.ACK.rawValue) {
            rcvAckNum = pkt.acknowledgmentNumber
            // seqCond.signal()
        }
        if pkt.hasFlags(TCPFlags.SYN.rawValue) {
            (sendAckNum,_) = pkt.sequenceNumber.addingReportingOverflow(1) // +1 for syn received
        }
        if pkt.hasFlags(TCPFlags.FIN.rawValue) {
            (sendAckNum,_) = sendAckNum.addingReportingOverflow(1)
        }
        
        switch state {
        case .LISTEN where pkt.SYN:
            state = .SYN_RCVD
            // attempt to connect to Ziti, pass in onWrite
            // if connect, send ACK=true, else send RST=true
            sourceAddr = pkt.ip.sourceAddress
            sourcePort = pkt.sourcePort
            destAddr = pkt.ip.destinationAddress
            destPort = pkt.destinationPort
            rcvWinScale = parseWinScale(pkt.options)
            //sendOldestUnAcked = UInt32.random(in: 0..<UInt32.max)
            
            tcpSend(nil, TCPFlags.SYN.rawValue|TCPFlags.ACK.rawValue, makeSynOpts())
        case .SYN_RCVD where pkt.RST:
            state = .LISTEN
        case .SYN_RCVD where pkt.ACK:
            state = .ESTABLISHED
        case .ESTABLISHED:
            if pkt.FIN {
                // TODO
            } else {
                NSLog("Established todo: handle these \(pkt.payload?.count ?? 0) bytes")
            }
        default:
            NSLog("Unexpected TCP state transistion for \(key)")
            onTCPSend(nil) // TODO: better way
        }
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
        if flags & (TCPFlags.SYN.rawValue|TCPFlags.FIN.rawValue) != 0 {
            (inc,_) = inc.addingReportingOverflow(1)
        }
        // TODO: not too sure about this...
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
