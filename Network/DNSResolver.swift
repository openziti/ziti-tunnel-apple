//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import NetworkExtension

class DNSResolver : NSObject {
    static let dnsPort:UInt16 = 53
    let tunnelProvider:PacketTunnelProvider
    
    var hostnamesLock = NSLock()
    var hostnames:[(name:String, ip:String, realIp:String?)] = []
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    // must be locked
    func findRecordsByName(_ name:String) -> [(name:String, ip:String, realIp:String?)] {
        return hostnames.filter{ return $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    
    func getIpRange(_ ip:Data, mask:Data) -> (first:Data, broadcast:Data) {
        var identity = Data(count:4)
        for i in 0..<4 {
            identity[i] = ip[i] & mask[i]
        }
        var first = Data(identity)
        if first[3] < 255 { first[3] = identity[3] + 1 }
        
        var broadcast = Data(count:4)
        for i in 0..<4 {
            broadcast[i] = (ip[i] | ~mask[i])
        }
        return (first, broadcast)
    }
    
    // Called before tunnel starts to save off the resolvedIp address if there is one
    // We can then proxy non-intercpted ports to this IP address
    private func resolveHostname(_ hostname:String) -> String? {
        let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
        CFHostStartInfoResolution(host, .addresses, nil)
        var success:DarwinBoolean = false
        if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? {
            for case let addr as NSData in addresses {
                var hn = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(addr.length),
                               &hn, socklen_t(hn.count), nil, 0, NI_NUMERICHOST) == 0 {
                    // keep as loop for now - may need to come back to this and filter out non IPv4 results
                    let ipStr = String(cString: hn)
                    return ipStr
                }
            }
        }
        return nil
    }
    
    // must be locked
    func addHostname(_ name:String) -> String? {
        let ip = IPUtils.ipV4AddressStringToData(self.tunnelProvider.providerConfig.ipAddress)
        let mask = IPUtils.ipV4AddressStringToData(self.tunnelProvider.providerConfig.subnetMask)
        let (first, broadcast) = getIpRange(ip, mask:mask)
        
        var curr = Data(first)
        repeat {
            var inUse = false
            let fakeIpStr = curr.map{String(format: "%d", $0)}.joined(separator: ".")
            
            // skip addresses we know are in use
            let dnsSvrs = self.tunnelProvider.providerConfig.dnsAddresses
            if curr == ip || dnsSvrs.contains(fakeIpStr) || hostnames.first(where:{$0.ip==fakeIpStr}) != nil {
                inUse = true
            }
            
            // add it and get outta here
            if inUse == false {
                let realIpStr = resolveHostname(name)
                NSLog("Real IP for \(name) = \(realIpStr ?? "nil")")
                hostnames.append((name:name, ip:fakeIpStr, realIp:realIpStr))
                return fakeIpStr
            }
            
            // advance to next ip addr
            for i in (0..<4).reversed() {
                if curr[i] == 255 { curr[i] = 0 }
                else { curr[i] += 1 }
                if curr[i] > 0 { break }
            }
        } while curr != broadcast
        return nil
    }
    
    func needsResolution(_ udp:UDPPacket) -> Bool {
        let dnsAddresses = self.tunnelProvider.providerConfig.dnsAddresses
        if udp.destinationPort == DNSResolver.dnsPort &&
            dnsAddresses.contains(udp.ip.destinationAddressString) == true {
            return true
        }
        return false
    }
    
    func resolve(_ udp:UDPPacket) {
        guard let dns = DNSPacket(udp) else { return }
        
        //NSLog("DNS-->: \(dns.debugDescription)")
        // only resolve queries (should never see this...)
        if dns.qrFlag { return }
        
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
                hostnamesLock.lock()
                let matches = findRecordsByName(q.name.nameString)
                hostnamesLock.unlock()
                
                if (matches.count > 0) {
                    if (q.recordType == DNSRecordType.A) {
                        responseCode = DNSResponseCode.noError
                        matches.forEach { result in
                            let data = IPUtils.ipV4AddressStringToData(result.ip)
                            let ans = DNSResourceRecord(result.name,
                                                        recordType:DNSRecordType.A,
                                                        recordClass:DNSRecordClass.IN,
                                                        ttl:0,
                                                        resourceData:data)
                            answers.append(ans)
                            NSLog("DNS: \(result.name) -> \(result.ip)")
                        }
                    } else {
                        // AAAA with matches, return nameError
                        responseCode = DNSResponseCode.nameError
                    }
                } else if inMatchDomains {
                    responseCode = DNSResponseCode.nameError
                } else {
                    // Sending `refused` no longer works since Catalina updata.  Attempt to resolve, see if I get into infinate loop
                    //responseCode = DNSResponseCode.refused
                    
                    responseCode = DNSResponseCode.nameError
                    if let ip = resolveHostname(q.name.nameString) {
                        let data = IPUtils.ipV4AddressStringToData(ip)
                        let ans = DNSResourceRecord(q.name.nameString,
                                                    recordType:DNSRecordType.A,
                                                    recordClass:DNSRecordClass.IN,
                                                    ttl:0,
                                                    resourceData: data)
                        answers.append(ans)
                        //NSLog("System DNS: \(q.name.nameString) -> \(ip)")
                    }
                }
            }
        }
        
        let dnsR = DNSPacket(dns, questions:dns.questions, answers:answers)
        dnsR.responseCode = responseCode
        dnsR.udp.updateLengthsAndChecksums()
        
        //NSLog("<--DNS: \(dnsR.debugDescription)")
        //NSLog("<--UDP: \(dnsR.udp.debugDescription)")
        //NSLog("<--IP: \(dnsR.udp.ip.debugDescription)")
 
        tunnelProvider.writePacket(dnsR.udp.ip.data)
    }
    
    private func inMatchDomains(_ qName:String) -> Bool {
        let domains = self.tunnelProvider.providerConfig.dnsMatchDomains
        return domains.contains{ domain in
            return qName == domain || qName.hasSuffix("."  + domain)
        }
    }
}
