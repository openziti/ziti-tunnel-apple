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
