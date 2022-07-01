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

// convenience..
class IPUtils {
    static func ipV4AddressStringToData(_ ipString:String) -> Data {
        var data = Data()
        autoreleasepool {
            let ipParts:[String] = ipString.components(separatedBy: ".")
            ipParts.forEach { part in
                let b = UInt8((part as NSString).integerValue)
                data.append(b)
            }
        }
        return data
    }
    
    static func isValidIpV4Address(_ str:String) -> Bool {
        var isValid = false
        autoreleasepool {
            let addr = str.trimmingCharacters(in: .whitespaces)
            let parts = addr.components(separatedBy: ".")
            let nums = parts.compactMap { Int($0) }
            isValid =  parts.count == 4 && nums.count == 4 && nums.filter { $0 >= 0 && $0 < 256}.count == 4
        }
        return isValid
    }
    
    static func areSameRoutes(_ r1:NEIPv4Route, _ r2:NEIPv4Route) -> Bool {
        var areSame = true
        autoreleasepool {
            let r1A = ipV4AddressStringToData(r1.destinationAddress)
            let r1M = ipV4AddressStringToData(r1.destinationSubnetMask)
            let r2A = ipV4AddressStringToData(r2.destinationAddress)
            let r2M = ipV4AddressStringToData(r2.destinationSubnetMask)
            
            for ((r1A, r1M), (r2A, r2M)) in zip(zip(r1A, r1M), zip(r2A, r2M)) {
                if (r1A & r1M) != (r2A & r2M) {
                    areSame = false
                    break
                }
            }
        }
        return areSame
    }
    
    static func inV4Subnet(_ dest:Data, network:Data, mask:Data) -> Bool {
        var inSubnet = true
        autoreleasepool {
            for (dest, (network, mask)) in zip(dest, zip(network, mask)) {
                if (dest & mask) != (network & mask) {
                    inSubnet = false
                    break
                }
            }
        }
        return inSubnet
    }
}
