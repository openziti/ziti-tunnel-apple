//
//  DNSName.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/25/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

class DNSName : NSObject {
    var nameString = ""
    var numBytes = 0
    
    init(_ data:Data, offset:Int) {
        super.init()
        var count = 0
        var keepCountingBytes = true
        var done = false
        var currOffset = offset
        
        while !done {
            let countOrOffset:UInt8 = data[data.startIndex + currOffset]
            if isAnOffset(countOrOffset) {
                currOffset = Int(countOrOffset)
                count = findCountAndOffset(data, offset:&currOffset)
                if keepCountingBytes {
                    self.numBytes += 2
                }
                keepCountingBytes = false
            } else {
                count = Int(countOrOffset)
                if keepCountingBytes {
                    self.numBytes += (count + 1)
                }
            }
            if count == 0 {
                done = true
            } else {
                if !self.nameString.isEmpty {
                    self.nameString += "."
                }
                
                let indx = data.startIndex + currOffset + 1
                for i in indx..<(count+indx) {
                    self.nameString += String(UnicodeScalar(data[i]))
                }
                currOffset += (count + 1)
            }
        }
    }
    
    init(_ nameString:String) {
        self.nameString = nameString
        self.numBytes = nameString.count + 2 // leading count, trailing 0x00
    }
    
    private func isAnOffset(_ value:UInt8) -> Bool {
        // if first two bits are set, we have a new offset
        return (value & 0xc0) == 0xc0
    }
    
    private func findCountAndOffset(_ data:Data, offset: inout Int) -> Int {
        let countOrOffset:UInt8 = data[data.startIndex + offset]
        if isAnOffset(countOrOffset) {
            // new offset is made from last 14 bits of two bytes
            offset = Int(IPUtils.extractUInt16(data, from: data.startIndex + offset) & 0x3f)
            return findCountAndOffset(data, offset:&offset)
        } else {
            return Int(countOrOffset)
        }
    }
}
