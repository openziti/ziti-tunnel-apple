//
//  PacketRouter.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/24/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension
import Foundation

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

class PacketRouter : NSObject {
    
    let tunnelProvider:PacketTunnelProvider
    
    init(tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    private func isSelfDnsMessage(_ udp:UDPPacket) -> Bool {
        let conf = self.tunnelProvider.conf
        if let dns = conf["dns"] {
            let dnsServers = (dns as! String).components(separatedBy: ",")
            if udp.destinationPort == 53 && dnsServers.contains(udp.ip.destinationAddressString) {
                return true
            }
        }
        return false
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
    
    private func ipAddressStringToData(_ ipString:String) -> Data {
        var data = Data()
        let ipParts:[String] = ipString.components(separatedBy: ".")
        ipParts.forEach { part in
            // f'ing swift strings.  punting to obj-c...
            let b = UInt8((part as NSString).integerValue)
            data.append(b)
        }
        return data
    }
    
    private func processDNS(_ dns:DNSPacket) {
        NSLog("DNS-->: \(dns.debugDescription)")
        
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
            // only respond to type A, class IN, other respond with 'not implemented'
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
                    let data = ipAddressStringToData(result.intercept)
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
                // TODO: forward to onward DNS
                NSLog("...TODO: forward to onward DNS")
            }
        }
    }
    
    private func inSubnet(_ ip:IPv4Packet) -> Bool {
        let conf = self.tunnelProvider.conf
        if let ipAddress = conf["ip"], let subnetMask = conf["subnet"] {
            let ipAddressData = ipAddressStringToData(ipAddress as! String)
            let subnetMaskData = ipAddressStringToData(subnetMask as! String)
            
            for (dest, (ip, mask)) in zip(ip.destinationAddress, zip(ipAddressData, subnetMaskData)) {
                if (dest & mask) != (ip & dest) {
                    return false
                }
            }
        }
        return true
    }
    
    private func routeUDP(_ udp:UDPPacket) {
        NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if isSelfDnsMessage(udp) {
            if let dns = DNSPacket(udp) {
                // ignore response messages (shouldn't ever see any..)
                if !dns.qrFlag {
                    processDNS(dns)
                }
            }
        } else {
            // TODO: --> Ziti
            NSLog("...TODO: --> looks meant for Ziti")
        }
    }
    
    func route(_ data:Data) {
        if let ip = IPv4Packet(data) {
            NSLog("IP-->: \(ip.debugDescription)")
            
            // drop/log any messages that aren't destinated for our subnet (e.g., SSDP broadcast messages)
            if !inSubnet(ip) {
                NSLog("...dropping message (not in subnet)")
            } else {
                switch ip.protocolId {
                case IPv4ProtocolId.UDP:
                    if let udp = UDPPacket(ip) {
                        routeUDP(udp)
                    }
                case IPv4ProtocolId.TCP:
                    NSLog("route TCP: TODO...")
                default:
                    NSLog("No route for protocol \(ip.protocolId)")
                }
            }
        }
    }
}
