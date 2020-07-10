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

struct IPv4Flags : OptionSet {
    let rawValue: UInt8
    static let moreFragments = IPv4Flags(rawValue: 1 << 0)
    static let dontFragment  = IPv4Flags(rawValue: 1 << 1)
    static let reserved      = IPv4Flags(rawValue: 1 << 2)
}

class IPv4Packet : NSObject, IPPacket {
    static let version4:UInt8 = 4
    static let headerWordLength = 4
    static let minHeaderLength:UInt8 = 5
    static let minHeaderBytes = 20
    static let defaultTtl:UInt8 = 64
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
        guard data.count >= IPv4Packet.minHeaderBytes else { return nil }
        self.data = data
        super.init()
        guard self.totalLength <= data.count else { return nil }
    }
    
    init?(count:Int) {
        guard count >= IPv4Packet.minHeaderLength else { return nil }
        self.data = Data(count: count)
        super.init()
        self.version = IPv4Packet.version4
        self.headerLength = IPv4Packet.minHeaderLength
        self.identification = self.genIdentificationNumber()
        self.flags = IPv4Flags.dontFragment
        self.ttl = IPv4Packet.defaultTtl
    }
    
    func createFromRefPacket(_ refPacket: IPPacket) -> IPPacket {
        let ip = IPv4Packet(count:(IPv4Packet.minHeaderBytes))!
        ip.version = IPv4Packet.version4
        ip.headerLength = IPv4Packet.minHeaderLength
        ip.identification = ip.genIdentificationNumber()
        ip.flags = IPv4Flags.dontFragment
        ip.ttl = IPv4Packet.defaultTtl
        ip.protocolId = refPacket.protocolId
        ip.sourceAddress = refPacket.destinationAddress
        ip.destinationAddress = refPacket.sourceAddress
        return ip
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
        get { return IPUtils.extractUInt16(data, from: IPv4Packet.totalLengthOffset) }
        set { IPUtils.updateUInt16(&data, at: IPv4Packet.totalLengthOffset, value: newValue) }
    }
    
    var identification:UInt16 {
        get { return IPUtils.extractUInt16(data, from: IPv4Packet.identificationOffset) }
        set { IPUtils.updateUInt16(&data, at: IPv4Packet.identificationOffset, value: newValue) }
    }
    
    var flags:IPv4Flags {
        get { return IPv4Flags(rawValue: data[IPv4Packet.flagsAndFragementsOffset] >> 5) }
        set { data[IPv4Packet.flagsAndFragementsOffset] = (newValue.rawValue << 5) | data[IPv4Packet.flagsAndFragementsOffset] & 0x1f }
    }
    
    var fragmentOffset:UInt16 {
        get { return IPUtils.extractUInt16(data, from: IPv4Packet.flagsAndFragementsOffset) & 0x1fff }
        set {
            let prev = data[IPv4Packet.flagsAndFragementsOffset]
            IPUtils.updateUInt16(&data, at: IPv4Packet.flagsAndFragementsOffset, value: newValue & 0x1fff)
            data[IPv4Packet.flagsAndFragementsOffset] = (prev & 0xe0) | (data[IPv4Packet.flagsAndFragementsOffset] & 0x1f)
        }
    }
    
    var ttl:UInt8 {
        get { return data[IPv4Packet.ttlOffset] }
        set { data[IPv4Packet.ttlOffset] = newValue }
    }
    
    var protocolId:IPProtocolId {
        get { return IPProtocolId(data[IPv4Packet.protocolOffset]) }
        set { data[IPv4Packet.protocolOffset] = newValue.rawValue }
    }
    
    var headerChecksum:UInt16 {
        get { return IPUtils.extractUInt16(data, from: IPv4Packet.headerChecksumOffset) }
        set { IPUtils.updateUInt16(&data, at: IPv4Packet.headerChecksumOffset, value: newValue) }
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
            guard self.headerLength > IPv4Packet.minHeaderLength else { return nil }
            let nOptsBytes = Int(self.headerLength - IPv4Packet.minHeaderLength) * IPv4Packet.headerWordLength
            return data[IPv4Packet.optionsOffset...(IPv4Packet.optionsOffset + nOptsBytes)]
        }
    }
    
    var payload:Data? {
        get {
            let startIndx = Int(self.headerLength) * IPv4Packet.headerWordLength
            guard startIndx < self.data.count else { return nil }
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
        var l16Header:[UInt16] = data[..<headerBytes].withUnsafeBytes{ urbp in
            urbp.bindMemory(to: UInt16.self).map(UInt16.init(bigEndian:))
        }
        l16Header[IPv4Packet.headerChecksumOffset/2] = 0x0000
        return IPUtils.computeChecksum(l16Header)
    }
    
    func updateHeaderChecksum() {
        self.totalLength = UInt16(self.data.count)
        self.headerChecksum = self.computeHeaderChecksum()
    }
    
    func updateLengthsAndChecksums() {
        self.totalLength = UInt16(self.data.count)
        self.updateHeaderChecksum()
    }
    
    private static var identificationCounter:UInt16 = 0
    func genIdentificationNumber() -> UInt16 {
        let newId = IPv4Packet.identificationCounter % UInt16.max
        (IPv4Packet.identificationCounter,_) = IPv4Packet.identificationCounter.addingReportingOverflow(1)
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
        if flags.contains(IPv4Flags.dontFragment) { s += " (Don't Fragment)" }
        if flags.contains(IPv4Flags.moreFragments) { s += " (More Fragments)" }
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
            s += IPUtils.payloadToString(payload)
        }
        return s
    }
}
