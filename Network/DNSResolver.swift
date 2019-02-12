//
//  DNSResolver.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/25/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation
import NetworkExtension


// for some quick testing (could do simple UI, will eventuall come from Ziti for names,
// internal 'find any open' for intercepts..)
fileprivate var dnsLookup:[(name:String, intercept:String)] = [
    ("google.services.netfoundry.io", "74.125.201.99"),
    ("gotcha.services.netfoundry.io", "169.254.126.101")
]

/*
 fileprivate var interceptLookup:[(name:String, intercept:String)] = [
 ("169.254.126.101", "ziti-controller-test-01.netfoundry.io")
 ]
 */

class DNSResolver : NSObject {
    
    static let dnsPort:UInt16 = 53
    
    let tunnelProvider:PacketTunnelProvider
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    func needsResolution(_ udp:UDPPacket) -> Bool {
        let dnsAddresses = self.tunnelProvider.providerConfig.dnsAddresses
        if udp.destinationPort == DNSResolver.dnsPort && dnsAddresses.contains(udp.ip.destinationAddressString) {
            return true
        }
        return false
    }
    
    func resolve(_ udp:UDPPacket) {
        guard let dns = DNSPacket(udp) else {
            NSLog("ATTEMPT TO RESOLVE NON DNS MESSAGE")
            return
        }
        
        NSLog("DNS-->: \(dns.debugDescription)")
        
        // only resolve queries (should never see this...)
        if dns.qrFlag {
            NSLog("ATTEMPT TO RESOLVE RESPONSE MESSAGE")
            return
        }
        
        var answers:[DNSResourceRecord] = []
        var inMatchDomains = false
        var responseCode:DNSResponseCode = DNSResponseCode.notImplemented
    
        // Respond only to single Query. If multiple queries, respond notImplemented (defacto standard)
        if dns.questions.count == 1 {
            let q:DNSQuestion = dns.questions[0]
            
            // respond to all queries if matching names (.nameError if unable to respolve)
            inMatchDomains = self.inMatchDomains(q.name.nameString)
            
            //
            // Only give a valid response to A requests
            // - if find matches, return 'em
            // - if no match, but in a matching domain, return nameError
            // - otherwise if no match, reject (allowing next resolver to respond
            // For AAAA requests
            // - if find matches, return nameError
            // - if no match, reject
            //
            if q.recordType == DNSRecordType.A || q.recordType == DNSRecordType.AAAA {
                let matches = dnsLookup.filter{ return $0.0 == q.name.nameString }
                
                if (matches.count > 0) {
                    if (q.recordType == DNSRecordType.A) {
                        responseCode = DNSResponseCode.noError
                        matches.forEach {result in
                            let data = IPUtils.ipV4AddressStringToData(result.intercept)
                            let ans = DNSResourceRecord(result.name,
                                                        recordType:DNSRecordType.A,
                                                        recordClass:DNSRecordClass.IN,
                                                        ttl:0,
                                                        resourceData:data)
                            answers.append(ans)
                        }
                    } else {
                        // AAAA with matches, return nameError
                        responseCode = DNSResponseCode.nameError
                    }
                } else if inMatchDomains {
                    responseCode = DNSResponseCode.nameError
                } else {
                    responseCode = DNSResponseCode.refused
                }
            }
        }
        
        let dnsR = DNSPacket(dns, questions:dns.questions, answers:answers)
        dnsR.responseCode = responseCode
        dnsR.udp.updateLengthsAndChecksums()
        
        NSLog("<--DNS: \(dnsR.debugDescription)")
        NSLog("<--UDP: \(dnsR.udp.debugDescription)")
        NSLog("<--IP: \(dnsR.udp.ip.debugDescription)")
        
        // write response to tun (returns false on error, but nothing to do if it fails...)
        if self.tunnelProvider.packetFlow.writePackets([dnsR.udp.ip.data],
                                                       withProtocols: [AF_INET as NSNumber]) == false {
            NSLog("### Faild writing DNS response packet")
        }
    }
    
    private func inMatchDomains(_ qName:String) -> Bool {
        let domains = self.tunnelProvider.providerConfig.dnsMatchDomains
        return domains.contains{ domain in
            return qName == domain || qName.hasSuffix("."  + domain)
        }
    }
}
