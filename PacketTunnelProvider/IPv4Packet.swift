//
//  IPv4Packet.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

class IPv4Packet : NSObject {
    var data:Data
    
    init?(data: Data) {
        if data.count < 20 {
            NSLog("Invalid IPv4 Packet size \(data.count)")
            return nil
        }
        
        self.data = data
        super.init()
        
        if self.totalLength > data.count {
            NSLog("Invalid IPv4 Packet length totalLenght=\(self.totalLength), buffer size=\(data.count)")
            return nil
        }
    }
    
    init?(count:Int) {
        if (count < 20) {
            NSLog("Invalid IPv4 Packet size \(count)")
            return nil
        }
        self.data = Data(count: count)
    }
    
    var version:UInt8 {
        get { return data[0] >> 4 }
        set { data[0] = (newValue << 4) | (data[0] & 0x0f) }
    }
    
    var headerLength:UInt8 {
        get { return data[0] & 0x0f }
        set { data[0] = (data[0] & 0xf0) | (newValue & 0x0f) }
    }
    
    var dscp:UInt8 {
        get { return data[1] >> 2 }
        set { data[1] = (data[1] & 0xc0) | (newValue & 0x3f) }
    }
    
    var ecn:UInt8 {
        get { return data[1] & 0x03 }
        set { data[1] = (data[1] & 0xfc) | (newValue & 0x03) }
    }
    
    var totalLength:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: 2) }
        set { IPv4Utils.updateUInt16(&data, at: 2, value: newValue) }
    }
    
    var identification:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: 4) }
        set { IPv4Utils.updateUInt16(&data, at: 4, value: newValue) }
    }
    
    var flags:UInt8 {
        get { return data[6] >> 5 }
        set { data[6] = (data[6] & 0xe0) | (newValue & 0x1f) }
    }
    
    var fragmentOffset:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: 6) & 0x1fff }
        set {
            let prev = data[6]
            IPv4Utils.updateUInt16(&data, at: 6, value: newValue)
            data[6] = (prev & 0xe0) | (data[6] & 0x1f)
        }
    }
    
    var ttl:UInt8 {
        get { return data[8] }
        set { data[8] = newValue }
    }
    
    var protocolId:UInt8 {
        get { return data[9] }
        set { data[9] = newValue }
    }
    
    var headerChecksum:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: 10) }
        set { IPv4Utils.updateUInt16(&data, at: 10, value: newValue) }
    }
    
    var sourceAddress : Data {
        get { return data[12...15] }
        set { data.replaceSubrange(12...15, with: newValue) }
    }
    
    var destinationAddress : Data {
        get { return data[16...19] }
        set { data.replaceSubrange(16...19, with: newValue) }
    }
    
    var options:Data? {
        get {
            if (self.headerLength == 5) {
                return nil
            }
            
            let nOptsBytes = Int(self.headerLength - 5) * 4
            return data[20...(20+nOptsBytes)]
        }
        
        //set {
            // TODO (remove if there, insert newValue if not nill, updata totalLength)
        //}
    }
    
    var payload:Data? {
        get {
            let startIndx = Int(self.headerLength) * 4
            if (startIndx >= self.data.count) {
                return nil
            }
            return self.data[startIndx...]
        }
        
        set {
            let startIndx = Int(self.headerLength) * 4
            if let nv = newValue {
                if startIndx < self.data.count {
                    self.data.replaceSubrange(startIndx..., with:nv)
                } else {
                    self.data.append(nv)
                }
            } else if startIndx < self.data.count {
                self.data.removeSubrange(startIndx...)
            }
            self.totalLength = UInt16(self.data.count)
        }
    }
    
    var protocolString: String {
        get {
            var s = ""
            switch self.protocolId {
            case UInt8(IPPROTO_UDP):  s = "UDP"
            case UInt8(IPPROTO_TCP):  s = "TCP"
            case UInt8(IPPROTO_ICMP): s = "ICMP"
            default: s = String(self.protocolId)
            }
            return s
        }
    }
    
    var sourceAddressString: String {
        get { return sourceAddress.map{String(format: "%d", $0)}.joined(separator: ".") }
    }
    
    var destinationAddressString: String {
        get { return destinationAddress.map{String(format: "%d", $0)}.joined(separator: ".") }
    }
    
    func computeHeaderChecksum() -> UInt16 {
        
        // copy the header into UInt16 array, network order
        let headerBytes = self.headerLength * 4
        var l16Header:[UInt16] = self.data[..<headerBytes].withUnsafeBytes {
            UnsafeBufferPointer<UInt16>(start: $0, count: Int(headerBytes/2)).map(UInt16.init(bigEndian:))
        }
        
        // zero out the checksum in copied header
        l16Header[5] = 0x0000
        
        // 0 is prev result, 1 is UInt16, return next result
        var sum:UInt32 = l16Header.reduce(0x0000ffff) { (prevSum, curr) in
            var newSum:UInt32 = prevSum + UInt32(curr)
            if newSum > 0xffff {
                newSum -= 0xffff
            }
            return newSum
        }
        
        // untested.., (should never execute for any of the hecksums computed here)
        if (headerBytes % 2) != 0 {
            let lastWord = UInt16(self.data[Int(headerBytes-1)]) << 8
            sum += UInt32(lastWord) //byte order?
            if sum > 0xffff {
                sum -= 0xffff
            }
        }
        
        return UInt16(~sum & 0xffff)
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(version), Src: \(sourceAddressString), Dest:\(destinationAddressString)\n"
        
        s += "\n" +
            "   version: \(version)\n" +
            "   headerLength: \(headerLength)\n" +
            "   dscp:\(String(format:"0x%2x", dscp))\n" +
            "   ecn: \(ecn)\n" +
            "   totalLength: \(totalLength)\n" +
            "   identification: \(String(format:"0x%2x", identification)) (\(identification))\n" +
            "   flags: \(String(format:"0x%2x", flags))\n" +
            "   fragmentOffset: \(fragmentOffset)\n" +
            "   ttl: \(ttl)\n" +
            "   protocol: \(protocolString) (\(protocolId))\n" +
            "   headerChecksun: \(String(format:"0x%2x", headerChecksum))\n" +
            "   computedChecksun: \(String(format:"0x%2x", computeHeaderChecksum()))\n" +
            "   sourceAddress: \(sourceAddressString)\n" +
            "   destinationAddress: \(destinationAddressString)\n"
        
        if let opts = self.options {
            s += "   options: \(opts.map{String(format: "%02X ", $0)}.joined())"
        }
        
        if let payload = self.payload {
            s += IPv4Utils.payloadToString(payload)
        }
        
        return s
    }
}
