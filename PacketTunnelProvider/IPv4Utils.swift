//
//  IPv4Utils.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

// convenience..
class IPv4Utils {
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
