//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import NetworkExtension

class DNSResolver : NSObject {
    static let dnsPort:UInt16 = 53
    let tunnelProvider:PacketTunnelProvider
    
    class DnsEntry : NSObject {
        let hostname:String
        let ip:String
        var serviceIds:[String] = []
        
        init(_ hostname:String, _ ip:String, _ serviceId:String) {
            self.hostname = hostname
            self.ip = ip
            self.serviceIds.append(serviceId)
        }
    }
    var dnsEntries:[DnsEntry] = []
    var dnsLock = NSLock()
    
    var hostnames:[String] {
        var nms:[String] = []
        dnsLock.lock()
        dnsEntries.forEach { nms.append($0.hostname) }
        dnsLock.unlock()
        return nms
    }
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
    }
    
    func findRecordsByName(_ name:String) -> [(name:String, ip:String)] {
        dnsLock.lock()
        let entries = dnsEntries.filter{ return $0.hostname.caseInsensitiveCompare(name) == .orderedSame }
        var matches:[(name:String, ip:String)] = []
        entries.forEach { e in
            matches.append((name:e.hostname, ip:e.ip))
        }
        dnsLock.unlock()
        return matches
    }
    
    func addDnsEntry(_ hostname:String, _ ip:String, _ serviceId: String) {
        dnsLock.lock()
        let matches = dnsEntries.filter{ return $0.hostname.caseInsensitiveCompare(hostname) == .orderedSame }
        if matches.count > 0 {
            matches.forEach { m in
                m.serviceIds.append(serviceId)
            }
        } else {
            let newEntry = DnsEntry(hostname, ip, serviceId)
            dnsEntries.append(newEntry)
        }
        dnsLock.unlock()
    }
    
    func removeDnsEntry(_ serviceId:String) {
        dnsLock.lock()
        
        // drop this serviceId from all entries
        dnsEntries.forEach { e in
            e.serviceIds = e.serviceIds.filter { $0 != serviceId }
        }
        
        // drop all entries with no service Id
        dnsEntries = dnsEntries.filter { $0.serviceIds.count > 0 }
        dnsLock.unlock()
    }
    
    func dumpDns() {
        dnsLock.lock()
        dnsEntries.forEach { e in
            zLog.debug("hostname: \(e.hostname), ip: \(e.ip), serviceIds: \(e.serviceIds)")
        }
        dnsLock.unlock()
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
    
    // To resolve IP addresses we are not intercepting
    func resolveHostname(_ hostname:String, _ recordType:DNSRecordType) -> String? {
        let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
        CFHostStartInfoResolution(host, .addresses, nil)
        var success:DarwinBoolean = false
        if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? {
            for case let addr as NSData in addresses {
                var hn = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(addr.length),
                               &hn, socklen_t(hn.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(cString: hn)
                    if recordType == .A && IPUtils.isValidIpV4Address(ipStr) {
                        return ipStr
                    } else if recordType == .AAAA {
                        return ipStr
                    }
                }
            }
        }
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
        
        //zLog.trace("DNS-->: \(dns.debugDescription)")
        // only resolve queries (should never see this...)
        if dns.qrFlag { return }
        
        var answers:[DNSResourceRecord] = []
        var responseCode:DNSResponseCode = DNSResponseCode.notImplemented
    
        // Respond only to single Query. If multiple queries, respond notImplemented (defacto standard)
        if dns.questions.count == 1 {
            let q:DNSQuestion = dns.questions[0]
            
            //
            // Only give a valid response to A requests
            // - if find matches, return 'em
            // - if no match, but in a matching domain, return nameError
            // - otherwise if no match, reject (allowing next resolver to respond
            // For AAAA requests
            // - if find matches, return nameError
            // - if no match, reject
            //
            if (q.recordType == DNSRecordType.A || q.recordType == DNSRecordType.AAAA) && q.recordClass == DNSRecordClass.IN {
                let matches = findRecordsByName(q.name.nameString)
                
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
                            zLog.info("DNS: \(result.name) -> \(result.ip)")
                        }
                    } else {
                        // AAAA with matches, return nameError
                        responseCode = DNSResponseCode.nameError
                    }
                } else {
                    responseCode = DNSResponseCode.nameError
                    if let ip = resolveHostname(q.name.nameString, q.recordType) {
                        if q.recordType == .A {
                            responseCode = DNSResponseCode.noError
                            let data = IPUtils.ipV4AddressStringToData(ip)
                            let ans = DNSResourceRecord(q.name.nameString,
                                                        recordType:DNSRecordType.A,
                                                        recordClass:DNSRecordClass.IN,
                                                        ttl:0,
                                                        resourceData: data)
                            answers.append(ans)
                            zLog.trace("System DNS: \(q.name.nameString) -> \(ip)")
                        } else if q.recordType == .AAAA {
                            // TODO: need to write IPUtils.ipV6AddressStringToData(ip)
                            // for now return nameError, which should inspire request for .A
                            // zLog.info("DNSResolver returning NXDomain instead of \(q.name.nameString) -> \(ip) ")
                        }
                    }
                }
            }
        }
        
        let dnsR = DNSPacket(dns, questions:dns.questions, answers:answers)
        dnsR.responseCode = responseCode
        dnsR.udp.updateLengthsAndChecksums()
        
        //zLog.trace("<--DNS: \(dnsR.debugDescription)")
        //zLog.trace("<--UDP: \(dnsR.udp.debugDescription)")
        //zLog.trace("<--IP: \(dnsR.udp.ip.debugDescription)")
 
        tunnelProvider.writePacket(dnsR.udp.ip.data)
    }
    
    private func inMatchDomains(_ qName:String) -> Bool {
        let domains = self.tunnelProvider.providerConfig.dnsMatchDomains
        return domains.contains{ domain in
            return qName == domain || qName.hasSuffix("."  + domain)
        }
    }
}
