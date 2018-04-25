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
    
    let tunnelProvider:PacketTunnelProvider
    let dnsProxy:DNSProxy
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
        self.dnsProxy = DNSProxy(tunnelProvider)
    }
    
    func needsResolution(_ udp:UDPPacket) -> Bool {
        let conf = self.tunnelProvider.conf
        if let dns = conf["dns"] {
            let dnsServers = (dns as! String).components(separatedBy: ",")
            if udp.destinationPort == 53 && dnsServers.contains(udp.ip.destinationAddressString) {
                return true
            }
        }
        return false
    }
    
    func resolve(_ udp:UDPPacket) {
        
        if let dns = DNSPacket(udp) {        
            NSLog("DNS-->: \(dns.debugDescription)")
            
            // only resolve queries ;) (should never see this...)
            if !dns.qrFlag {
                return
            }
            
            var answers:[DNSResourceRecord] = []
            var inMatchDomains = false
            var hasUnsupportedType = false
            
            dns.questions.forEach { q in
                
                // if any q.name is in our matchDomains, gonna reply one way or another
                // (found or not), otherwise if no matches, we need to forward this to onward DNS Server
                if inMatchDomains == false {
                    inMatchDomains = self.inMatchDomains(q.name.nameString)
                }
                
                //
                // only respond to type A, class IN, for others respond with 'not implemented'
                // btw - DNS standard says Question count 'usually' set to 1 on A/AAAA lookups.  Google tells me
                // BIND rejects requests that have more than 1 question...  I'll make a half-hearted
                // attempt to handle multiple...
                //
                if q.recordType != DNSRecordType.A || q.recordClass != DNSRecordClass.IN {
                    hasUnsupportedType = true
                } else {
                    
                    // possible we might match multiple IP addesses for same service...
                    let matches = dnsLookup.filter{ return $0.0 == q.name.nameString }
                    
                    matches.forEach {result in
                        let data = IPv4Utils.ipAddressStringToData(result.intercept)
                        let ans = DNSResourceRecord(result.name,
                                                    recordType:DNSRecordType.A,
                                                    recordClass:DNSRecordClass.IN,
                                                    ttl:0,
                                                    resourceData:data)
                        answers.append(ans)
                    }
                }
                
                //
                // If have answers or a question is in a match domain, respond.
                // Otherwise, forward to onward DNS server
                //
                NSLog("...have \(answers.count) answers, inMatchDomains=\(inMatchDomains)")
                if inMatchDomains || answers.count > 0 {
                    let dnsR = DNSPacket(dns, questions:dns.questions, answers:answers)
                    
                    if hasUnsupportedType {
                        dnsR.responseCode = DNSResponseCode.notImplemented
                    } else if answers.count != dns.questions.count {
                        dnsR.responseCode = DNSResponseCode.nameError
                    }
                    
                    // update checksume and lengths
                    dnsR.udp.updateLengthsAndChecksums()
                    
                    NSLog("<--DNS: \(dnsR.debugDescription)")
                    NSLog("<--UDP: \(dnsR.udp.debugDescription)")
                    NSLog("<--IP: \(dnsR.udp.ip.debugDescription)")
                    
                    // write response to tun (returns false on error, but nothing to do if it fails...)
                    self.tunnelProvider.packetFlow.writePackets([dnsR.udp.ip.data], withProtocols: [AF_INET as NSNumber])
                } else {
                    self.dnsProxy.proxyDnsMessage(dns)
                }
            }
        }
    }
    
    private func inMatchDomains(_ qName:String) -> Bool {
        let conf = self.tunnelProvider.conf
        if let matchDomains = conf["matchDomains"] {
            let domains = (matchDomains as! String).components(separatedBy: ",")
            return domains.contains{ domain in
                return qName == domain || qName.hasSuffix("."  + domain)
            }
        }
        return false
    }
}
