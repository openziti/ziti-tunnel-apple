//
//  IPv4Packet.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

struct IPv4Flags : OptionSet {
    let rawValue: UInt8
    
    static let moreFragments = IPv4Flags(rawValue: 1 << 0)
    static let dontFragment  = IPv4Flags(rawValue: 1 << 1)
    static let reserved      = IPv4Flags(rawValue: 1 << 2)
}

enum IPv4ProtocolId : UInt8 {
    case TCP = 6
    case UDP = 17
    case other
    
    init(_ byte:UInt8) {
        switch byte {
        case  6: self = .TCP
        case 17: self = .UDP
        default: self = .other
        }
    }
}

class IPv4Packet : NSObject {
    
    static let version4:UInt8 = 4
    
    static let headerWordLength = 4
    static let minHeaderLength:UInt8 = 5
    static let minHeaderBytes = 20
    static let defaultTtl:UInt8 = 255
    
    static let versionAndLengthOffset = 0
    static let totalLengthOffset = 2
    static let identificationOffset = 4
    static let flagsAndFragementsOffset = 6
    static let ttlOffset = 8
    static let protocolOffset = 9
    static let headerChecksumOffset = 10
    static let sourceAddressOffset = 12
    static let destinationAddressOffset = 16
    static let optionsOffset = 20
    
    var data:Data
    
    init?(_ data: Data) {
        if data.count < IPv4Packet.minHeaderBytes {
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
        if (count < IPv4Packet.minHeaderLength) {
            NSLog("Invalid IPv4 Packet size \(count)")
            return nil
        }
        self.data = Data(count: count)
        
        super.init()
        
        self.version = IPv4Packet.version4
        self.headerLength = IPv4Packet.minHeaderLength
    }
    
    var version:UInt8 {
        get { return data[IPv4Packet.versionAndLengthOffset] >> 4 }
        set {
            data[IPv4Packet.versionAndLengthOffset] =
                (newValue << 4) | (data[IPv4Packet.versionAndLengthOffset] & 0x0f)
        }
    }
    
    var headerLength:UInt8 {
        get { return data[IPv4Packet.versionAndLengthOffset] & 0x0f }
        set {
            data[IPv4Packet.versionAndLengthOffset] =
                (data[IPv4Packet.versionAndLengthOffset] & 0xf0) | (newValue & 0x0f)
        }
    }
    
    var totalLength:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: IPv4Packet.totalLengthOffset) }
        set { IPv4Utils.updateUInt16(&data, at: IPv4Packet.totalLengthOffset, value: newValue) }
    }
    
    var identification:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: IPv4Packet.identificationOffset) }
        set { IPv4Utils.updateUInt16(&data, at: IPv4Packet.identificationOffset, value: newValue) }
    }
    
    var flags:IPv4Flags {
        get { return IPv4Flags(rawValue: data[IPv4Packet.flagsAndFragementsOffset] >> 5) }
        set { data[IPv4Packet.flagsAndFragementsOffset] = (newValue.rawValue << 5) | data[IPv4Packet.flagsAndFragementsOffset] & 0x1f }
    }
    
    var fragmentOffset:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: IPv4Packet.flagsAndFragementsOffset) & 0x1fff }
        set {
            let prev = data[IPv4Packet.flagsAndFragementsOffset]
            IPv4Utils.updateUInt16(&data, at: IPv4Packet.flagsAndFragementsOffset, value: newValue & 0x1fff)
            data[IPv4Packet.flagsAndFragementsOffset] = (prev & 0xe0) | (data[IPv4Packet.flagsAndFragementsOffset] & 0x1f)
        }
    }
    
    var ttl:UInt8 {
        get { return data[IPv4Packet.ttlOffset] }
        set { data[IPv4Packet.ttlOffset] = newValue }
    }
    
    var protocolId:IPv4ProtocolId {
        get { return IPv4ProtocolId(data[IPv4Packet.protocolOffset]) }
        set { data[IPv4Packet.protocolOffset] = newValue.rawValue }
    }
    
    var headerChecksum:UInt16 {
        get { return IPv4Utils.extractUInt16(data, from: IPv4Packet.headerChecksumOffset) }
        set { IPv4Utils.updateUInt16(&data, at: IPv4Packet.headerChecksumOffset, value: newValue) }
    }
    
    var sourceAddress : Data {
        get { return data[IPv4Packet.sourceAddressOffset...(IPv4Packet.sourceAddressOffset+3)] }
        set {
            data.replaceSubrange(
                IPv4Packet.sourceAddressOffset...(IPv4Packet.sourceAddressOffset+3),
                with: newValue)
        }
    }
    
    var destinationAddress : Data {
        get { return data[IPv4Packet.destinationAddressOffset...(IPv4Packet.destinationAddressOffset+3)] }
        set {
            data.replaceSubrange(
                IPv4Packet.destinationAddressOffset...(IPv4Packet.destinationAddressOffset+3),
                with: newValue)
        }
    }
    
    var options:Data? {
        get {
            if (self.headerLength == IPv4Packet.minHeaderLength) {
                return nil
            }
            
            let nOptsBytes = Int(self.headerLength - IPv4Packet.minHeaderLength) * IPv4Packet.headerWordLength
            return data[IPv4Packet.optionsOffset...(IPv4Packet.optionsOffset + nOptsBytes)]
        }
        
        //set {
            // TODO (remove if there, insert newValue if not nill, updata totalLength)
        //}
    }
    
    var payload:Data? {
        get {
            let startIndx = Int(self.headerLength) * IPv4Packet.headerWordLength
            if (startIndx >= self.data.count) {
                return nil
            }
            return self.data[startIndx...]
        }
        
        set {
            let startIndx = Int(self.headerLength) * IPv4Packet.headerWordLength
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
    
    var sourceAddressString: String {
        get { return sourceAddress.map{String(format: "%d", $0)}.joined(separator: ".") }
    }
    
    var destinationAddressString: String {
        get { return destinationAddress.map{String(format: "%d", $0)}.joined(separator: ".") }
    }
    
    func computeHeaderChecksum() -> UInt16 {
        
        // copy the header into UInt16 array, network order
        let headerBytes = Int(self.headerLength) * IPv4Packet.headerWordLength
        var l16Header:[UInt16] = self.data[..<headerBytes].withUnsafeBytes {
            UnsafeBufferPointer<UInt16>(start: $0, count: Int(headerBytes/2)).map(UInt16.init(bigEndian:))
        }
        
        // zero out the checksum in copied header
        l16Header[IPv4Packet.headerChecksumOffset/2] = 0x0000
        
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
    
    func updateHeaderChecksum() {
        self.totalLength = UInt16(self.data.count)
        self.headerChecksum = self.computeHeaderChecksum()
    }
    
    private static var identificationCounter:UInt16 = 0
    func genIdentificationNumber() -> UInt16 {
        let newId = IPv4Packet.identificationCounter % UInt16.max
        IPv4Packet.identificationCounter += 1
        return newId
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(version), Src: \(sourceAddressString), Dest:\(destinationAddressString)\n"
        
        s += "\n" +
            "   version: \(version)\n" +
            "   headerLength: \(headerLength)\n" +
            "   totalLength: \(totalLength)\n" +
            "   identification: \(String(format:"0x%2x", identification)) (\(identification))\n" +
            "   flags: \(String(format:"0x%2x", flags.rawValue))"
        
        if flags.contains(IPv4Flags.dontFragment) {
            s += " (Don't Fragment)"
        }
        
        if flags.contains(IPv4Flags.moreFragments) {
            s += " (More Fragments)"
        }
            
        s += "\n" +
            "   fragmentOffset: \(fragmentOffset)\n" +
            "   ttl: \(ttl)\n" +
            "   protocol: \(protocolId)\n" +
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
