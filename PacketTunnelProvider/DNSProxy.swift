//
//  DNSProxy.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/25/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation
import NetworkExtension

class DNSProxy : NSObject {
    let tunnelProvider:PacketTunnelProvider
    
    // DNS transactionId:(sourPorce,timeSent)
    var requestLookup:[UInt16:(src:UDPPacket, timeSent:TimeInterval)] = [:]
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    // prune timed-out requests (give proxied DNS .5 secs to respond)
    private func reapRequestLut() {
        var newLut:[UInt16:(UDPPacket,TimeInterval)] = [:]
        self.requestLookup.forEach { entry in
            let currTime = NSDate().timeIntervalSinceNow
            if (currTime - entry.value.timeSent) < 0.5 {
                newLut[entry.key] = entry.value
            }
        }
        NSLog("DNSProxy: reaped \(self.requestLookup.count - newLut.count) entries")
        self.requestLookup = newLut
    }
    
    // What I'm going for here is a lazy property inialization that I can set to nill
    // and have re-init next time I access it...
    private func createSession() -> NWUDPSession {
        let session:NWUDPSession =  self.tunnelProvider.createUDPSession(
            to: NWHostEndpoint(hostname: "1.1.1.1", port: "53"),  // TODO: get forwardingDnsServer address from conf...
            from: nil)
        session.setReadHandler(self.handleDnsResponse, maxDatagrams: NSIntegerMax)
        return session
    }
    
    private var _session:NWUDPSession? = nil
    private var session:NWUDPSession? {
        get {
            if self._session == nil {
                self._session = createSession()
            }
            return self._session!
        }
        
        set {
            self._session = newValue
        }
    }
    
    private func handleDnsResponse(packets:[Data]?, error:Error?) {
        if let error = error {
            NSLog("Error handling read from forwarding DNS packet \(error)")
            return
        }
        
        if let packets = packets {
            for udpPayload in packets {
                let transactionId = IPv4Utils.extractUInt16(udpPayload, from: DNSPacket.idOffset)
                if let udpRequest = self.requestLookup.removeValue(forKey: transactionId) {
                    let udpResponse = UDPPacket(udpRequest.src, payload:udpPayload)
                    udpResponse.updateLengthsAndChecksums()
                    
                    NSLog("<--UDP: \(udpResponse.debugDescription)")
                    NSLog("<--IP: \(udpResponse.ip.debugDescription)")
                    self.tunnelProvider.packetFlow.writePackets([udpResponse.ip.data], withProtocols: [AF_INET as NSNumber])
                } else {
                    NSLog("Unable to corrolate DNS response to request for transactionId \(transactionId)")
                }
            }
        }
    }
    
    //
    // Here's what's going on:
    //  * create this session 'lazy' (this.session)
    //  * check the state
    //       if session is .ready, use if
    //       else if session .cancelled .failed or .invalid, kill session (and drop the packet)
    //       else if session .preparing or .waiting, drop the packet and move on (it'll be re-sent most likely...
    //
    func proxyDnsMessage(_ dns:DNSPacket) {
        
        // clean-up any timed-out requests
        self.reapRequestLut()
        
        if let udpPayload = dns.udp.payload {
            if let session = self.session {
                switch session.state {
                case .ready:
                    NSLog("...Forwarding DNS packet...")
                    
                    // cache the request so we know how to respond
                    self.requestLookup[dns.id] = (dns.udp, NSDate().timeIntervalSinceNow)
                    
                    session.writeDatagram(udpPayload, completionHandler: { error in
                        if let e = error {
                            NSLog("Error forwarding DNS packet \(e)")
                        }
                    })
                case .cancelled, .failed, .invalid:
                    NSLog("...Dropping DNS packet - forwarding session in invalid state. Re-creating...")
                    self.session = nil
                case .preparing, .waiting:
                    NSLog("...Dropping DNS packet - forwarding session not yet ready...")
                }
            }
        }
    }
}
