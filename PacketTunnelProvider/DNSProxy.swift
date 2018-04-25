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
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    //
    // What I'm going for here is a lazy property inialization that I can set to nill
    // and have re-init next time I access it...
    //
    private func createSession() -> NWUDPSession {
        // TODO: get forwardingDnsServer address from conf...
        let session:NWUDPSession =  self.tunnelProvider.createUDPSession(
            to: NWHostEndpoint(hostname: "1.1.1.1", port: "53"),
            from: nil)
        
        session.setReadHandler( { (packets, error) in
            if let e = error {
                NSLog("Error handling read from forwarding DNS packet \(e)")
                return
            }
            
            if let pkts = packets {
                for packet in pkts {
                    NSLog("Received response from onward DNS server:\n\(IPv4Utils.payloadToString(packet))")
                    
                    //let udp = UDPPacket(payload:packet)
                    //    set dest IP address to my IP.  set source to my DNS.  what f'ing port to use? need to store/lookup
                    // update checksums
                    // write to packet flow
                    /*NSLog("<--DNS: \(dnsR.debugDescription)")
                     NSLog("<--UDP: \(dnsR.udp.debugDescription)")
                     NSLog("<--IP: \(dnsR.udp.ip.debugDescription)")
                     
                     // write response to tun (returns false on error, but nothing to do if it fails...)
                     self.tunnelProvider.packetFlow.writePackets([dnsR.udp.ip.data], withProtocols: [AF_INET as NSNumber])*/
                }
            }
        }, maxDatagrams: NSIntegerMax)
        
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
    
    //
    // Here's what's going on:
    //  * create this session 'lazy' (dnsForwardingSession)
    //  * check the state
    //       if session is .ready, use if
    //       else if session .cancelled .failed or .invalid, kill session (and drop the packet)
    //       else if session .preparing or .waiting, drop the packet and move on (it'll be re-sent most likely...
    //
    func proxyDnsMessage(_ dns:DNSPacket) {
        if let udpPayload = dns.udp.payload {
            if let session = self.session {
                switch session.state {
                case .ready:
                    NSLog("...Forwarding DNS packet...")
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
