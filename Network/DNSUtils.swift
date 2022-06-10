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

class DNSUtils : NSObject {
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
    
    class DnsEntries : NSObject {
        var entries:[DnsEntry] = []
        var hostnames:[String] {
            var nms:[String] = []
            entries.forEach { nms.append($0.hostname) }
            return nms
        }
        
        func add(_ hostname:String, _ ip:String, _ serviceId: String) {
            let matches = entries.filter{ return $0.hostname.caseInsensitiveCompare(hostname) == .orderedSame }
            if matches.count > 0 {
                matches.forEach { m in
                    m.serviceIds.append(serviceId)
                }
            } else {
                let newEntry = DnsEntry(hostname, ip, serviceId)
                entries.append(newEntry)
            }
        }
        
        func remove(_ serviceId:String) {
            // drop this serviceId from all entries
            entries.forEach { e in
                e.serviceIds = e.serviceIds.filter { $0 != serviceId }
            }
            
            // drop all entries with no service Id
            entries = entries.filter { $0.serviceIds.count > 0 }
        }
        
        func contains(_ addr:String) -> Bool {
            return entries.first(where: { $0.hostname == addr }) != nil
        }
        
        public override var debugDescription: String {
            var str = "DNS Entries:\n"
            entries.forEach { e in
                str += "\n   hostname: \(e.hostname), ip: \(e.ip), serviceIds: \(e.serviceIds)"
            }
            return str
        }
    }
    
    // To resolve IP addresses we are not intercepting
    class func resolveHostname(_ hostname:String) -> String? {
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
    
//    class func getFirstResolver(_ excludedRoute:NEIPv4Route) -> String? {
//        var firstResolver:String?
//        var state = __res_9_state()
//        res_9_ninit(&state)
//
//        let maxServers = 20 // NI_MAXSERV
//        var servers = [res_9_sockaddr_union](repeating: res_9_sockaddr_union(), count: maxServers)
//        let nServers = Int(res_9_getservers(&state, &servers, Int32(maxServers)))
//        for i in 0 ..< nServers {
//            var s = servers[i]
//
//            // only IPv4 supported by ziti-tunnel-sdk-c
//            if s.sin.sin_family != AF_INET {
//                zLog.info("Skipping non-IPv4 address")
//                continue
//            }
//            if s.sin.sin_len > 0 {
//                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
//                let sinLen = socklen_t(s.sin.sin_len)
//                let _ = withUnsafePointer(to: &s) {
//                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
//                        getnameinfo($0, sinLen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
//                    }
//                }
//
//                let resolver = String(cString: hostBuffer)
//                let net = IPUtils.ipV4AddressStringToData(excludedRoute.destinationAddress)
//                let mask = IPUtils.ipV4AddressStringToData(excludedRoute.destinationSubnetMask)
//                let dest = IPUtils.ipV4AddressStringToData(resolver)
//                zLog.info("Cheking resolver \(i+1) of \(nServers): \(resolver)")
//                if IPUtils.inV4Subnet(dest, network: net, mask: mask) == false {
//                    firstResolver = resolver
//                    break
//                }
//            }
//        }
//        res_9_ndestroy(&state)
//
//        return firstResolver
//    }
    
    // The resolv9 code above only returns the nameservers for the first resolver.  That's great for getting the address
    // before the tunnel is connected, but not helpful after connected since the first resolver is now us.  So,
    // when network monitor triggers, we're gonna parse the results of `scutil --dns` to find the resolver to use for
    // fallback DNS...
    class func getFirstResolver(_ excludedRoute:NEIPv4Route) -> String? {
        var firstResolver:String?
#if os(macOS)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--dns"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        do {
            try task.run()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outputData, as: UTF8.self)
            let lines = output.split(whereSeparator: \.isNewline)
            
            var scoped = false
            for line in lines {
                if line == "DNS configuration (for scoped queries)" {
                    scoped = true
                }
                if scoped && line.starts(with: "  nameserver[") {
                    let comps = line.components(separatedBy: ":")
                    if comps.count == 2 {
                        let resolver = comps[1].trimmingCharacters(in: .whitespaces)
                        let net = IPUtils.ipV4AddressStringToData(excludedRoute.destinationAddress)
                        let mask = IPUtils.ipV4AddressStringToData(excludedRoute.destinationSubnetMask)
                        let dest = IPUtils.ipV4AddressStringToData(resolver)
                        if IPUtils.inV4Subnet(dest, network: net, mask: mask) == false {
                            firstResolver = resolver
                            break
                        }
                    }
                }
            }
        } catch {
            zLog.error(error.localizedDescription)
        }
#endif
        return firstResolver
    }
}
