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
    class DnsEntry : NSObject {
        let hostname:String
        let ip:String
        var serviceIds:[String] = []
        
        init(_ hostname:String, _ ip:String, _ serviceId:String) {
            self.hostname = hostname.lowercased()
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
    
    // To resolve IP addresses we are not intercepting
    func resolveHostname(_ hostname:String) -> String? {
        let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
        CFHostStartInfoResolution(host, .addresses, nil)
        var success:DarwinBoolean = false
        if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? {
            for case let addr as NSData in addresses {
                var hn = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(addr.length),
                               &hn, socklen_t(hn.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hn)
                }
            }
        }
        return nil
    }
}
