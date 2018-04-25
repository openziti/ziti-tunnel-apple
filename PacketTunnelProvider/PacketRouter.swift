//
//  PacketRouter.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/24/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension
import Foundation

// for some quick testing
fileprivate var intercepts:[(intercept:String, response:String)] = [
    ("google.services.netfoundry.io", "74.125.201.99"),
    ("gotcha.services.netfoundry.io", "169.254.126.101")
]

class PacketRouter : NSObject {
    
    let tunnelProvider:PacketTunnelProvider
    
    init(tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    func route(_ data:Data) {
        if let ipPacket = IPv4Packet(data) {
            if (ipPacket.protocolId == IPv4ProtocolId.UDP) {
                if let udp = UDPPacket(ipPacket) {
                    routeUDP(udp)
                }
            }
        }
    }
    
    private func routeUDP(_ udp:UDPPacket) {
        NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if udp.ip.destinationAddressString == self.tunnelProvider.selfDNS && udp.destinationPort == 53 {
            if let dns = DNSPacket(udp) {
                // only process requests...
                if !dns.qrFlag {
                    processDNS(dns)
                }
            }
        }
    }
    
    private func processDNS(_ dns:DNSPacket) {
        NSLog("DNS-->: \(dns.debugDescription)")
        
        //  quick and dirty to see if on right path
        var answers:[DNSResourceRecord] = []
        dns.questions.forEach { q in
            
            //NSLog("...process DNS question \(q.name.nameString), \(q.recordType), \(q.recordClass)")
            
            // only respond to type A, class IN
            if q.recordType == DNSRecordType.A && q.recordClass == DNSRecordClass.IN {
                let matches = intercepts.filter{ return $0.0 == q.name.nameString }
                
                matches.forEach {result in
                    var data = Data()
                    let ipParts:[String] = result.response.components(separatedBy: ".")
                    ipParts.forEach { part in
                        // f'ing swift strings.  punting...
                        let b = UInt8((part as NSString).integerValue)
                        data.append(b)
                    }
                    
                    let ans = DNSResourceRecord(result.intercept,
                                                recordType:DNSRecordType.A,
                                                recordClass:DNSRecordClass.IN,
                                                ttl:0,
                                                resourceData:data)
                    answers.append(ans)
                }
            }
            
            // This logic needs work (name error should only be sent back for single question)
            //     (should look at .notImplemented response as well...)
            //      maybe send one response per question?
            //
            NSLog("...have \(answers.count) answers")
            let dnsR = DNSPacket(dns, questions:dns.questions, answers:answers)
            if answers.count != dns.questions.count {
                dnsR.responseCode = DNSResponseCode.nameError
            }
            
            // update checksume and lengths
            dnsR.udp.updateLengthsAndChecksums()
            
            NSLog("<--DNS: \(dnsR.debugDescription)")
            NSLog("<--UDP: \(dnsR.udp.debugDescription)")
            NSLog("<--IP: \(dnsR.udp.ip.debugDescription)")
            
            // write response to tun (returns false on error, but nothing to do if it fails...)
            self.tunnelProvider.packetFlow.writePackets
        }
    }
}
