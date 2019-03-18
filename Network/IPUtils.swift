//
//  IPv4Utils.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

// convenience..
class IPUtils {
    static func extractUInt16(_ data:Data, from:Int) -> UInt16 {
        let byteArray = [UInt8](data.subdata(in: from..<(from+2)))
        return CFSwapInt16(UnsafePointer(byteArray).withMemoryRebound(to:UInt16.self, capacity: 1) {
            $0.pointee
        })
    }

    static func extractUInt32(_ data:Data, from:Int) -> UInt32 {
        let byteArray = [UInt8](data.subdata(in: from..<(from+4)))
        return CFSwapInt32(UnsafePointer(byteArray).withMemoryRebound(to:UInt32.self, capacity: 1) {
            $0.pointee
        })
    }

    static func updateUInt16(_ data: inout Data, at:Int, value:UInt16) {
        var swapped = CFSwapInt16(value)
        data.replaceSubrange(at..<(at+2), with: withUnsafeBytes(of: &swapped) { Array($0) })
    }
    
    static func appendUInt16(_ data: inout Data, value:UInt16) {
        var swapped = CFSwapInt16(value)
        data.append(contentsOf: withUnsafeBytes(of: &swapped) { Array($0) })
    }
    
    static func appendUInt32(_ data: inout Data, value:UInt32) {
        var swapped = CFSwapInt32(value)
        data.append(contentsOf: withUnsafeBytes(of: &swapped) { Array($0) })
    }
    
    static func ipV4AddressStringToData(_ ipString:String) -> Data {
        var data = Data()
        let ipParts:[String] = ipString.components(separatedBy: ".")
        ipParts.forEach { part in
            // f'ing swift strings.  punting to obj-c...
            let b = UInt8((part as NSString).integerValue)
            data.append(b)
        }
        return data
    }
    
    static func isValidIpV4Address(_ str:String) -> Bool {
        let addr = str.trimmingCharacters(in: .whitespaces)
        let parts = addr.components(separatedBy: ".")
        let nums = parts.compactMap { Int($0) }
        return parts.count == 4 && nums.count == 4 && nums.filter { $0 >= 0 && $0 < 256}.count == 4
    }
    
    static func inV4Subnet(_ dest:Data, network:Data, mask:Data) -> Bool {
        for (dest, (network, mask)) in zip(dest, zip(network, mask)) {
            if (dest & mask) != (network & mask) {
                return false
            }
        }
        return true
    }
    
    private static func v6SegToStr(_ seg:Data) -> String {
        return seg.map{String(format: "%x", $0)}.joined(separator: ":")
    }
    
    static let v6AddrNumWords = 8
    static func ipV6AddressToSting(_ addr:Data) -> String {
        var str = "::" // 'unspecified' or 'invalid'
        var addrWords:[UInt16] = addr.withUnsafeBytes {
            UnsafeBufferPointer<UInt16>(start: $0, count: Int(addr.count/2)).map(UInt16.init(bigEndian:))
        }

        let zeroSplit = addrWords.split(whereSeparator: { $0 != 0 }).max(by: {$1.count > $0.count})
        guard let z = zeroSplit else {
            return addrWords.map{String(format: "%x", $0)}.joined(separator: ":")
        }
        
        if z.count > 0 && z.count < IPUtils.v6AddrNumWords {
            if z.startIndex == 0 {
                str = "::" + addrWords[z.endIndex...].map{String(format: "%x", $0)}.joined(separator: ":")
            } else {
                str = addrWords[..<z.startIndex].map{String(format: "%x", $0)}.joined(separator: ":") + "::" + addrWords[z.endIndex...].map{String(format: "%x", $0)}.joined(separator: ":")
            }
        } else if z.count != IPUtils.v6AddrNumWords {
            str = addrWords.map{String(format: "%x", $0)}.joined(separator: ":")
        }
        return str
    }
    
    static func payloadToString(_ payload: Data) -> String {
        var i = 0
        var s = " " + payload.map {
            var str = String(format: "%02X", $0);
            i += 1; if (i%4)==0 { str += "\n"};
            return str
        }.joined(separator: " ")
        
        let unicodeScalars:[String] = payload.map  {
            if $0 < 0x21 || $0 > 0x7f {
                return String(UnicodeScalar("."))
            } else {
                return String(UnicodeScalar($0))
            }
        }
        s += "\n \(unicodeScalars.joined(separator: " "))"
        return s
    }
}
