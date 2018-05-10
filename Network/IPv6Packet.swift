//
//  IPv6Packet.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 5/7/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

enum IPv6NextHeader : UInt8 {
    case HOPOPT = 0
    case ICMP = 1
    case TCP = 6
    case UDP = 17
    case IPv6Route = 43
    case IPv6Frag = 44
    case ESP = 50
    case AH = 51
    case IPv6ICMP = 58
    case IPv6NoNxt = 59
    case IPv6Opts = 60
    case IPv6Mobility = 135
    case HIP = 139
    case other
    
    init(_ byte:UInt8) {
        switch byte {
        case 0: self = .HOPOPT
        case  1: self = .ICMP
        case  6: self = .TCP
        case 17: self = .UDP
        case 43: self = .IPv6Route
        case 44: self = .IPv6Frag
        case 50: self = .ESP
        case 51: self = .AH
        case 58: self = .IPv6ICMP
        case 59: self = .IPv6NoNxt
        case 60: self = .IPv6Opts
        case 135: self = .IPv6Mobility
        case 139: self = .HIP
        default: self = .other
        }
    }
    
    func isExtensionHeader() -> Bool {
        var isExtensionHeader = false
        switch self {
        case .HOPOPT, .IPv6Route, .IPv6Frag, .ESP, .AH, .IPv6NoNxt, .IPv6Opts, .IPv6Mobility, .HIP:
            isExtensionHeader = true
        default:
            break
        }
        return isExtensionHeader
    }
}

// TODO (currently set to 0 Target membership)
class IPv6Packet : NSObject, IPPacket {
    static let version6:UInt8 = 6
    
    static let numFirstHeaderBytes = 40
    static let defaultHopLimit:UInt8 = 255
    
    static let versionOffset = 0
    static let payloadLengthOffset = 4
    static let nextHeaderOffet = 6
    static let hopLimitOffset = 7
    static let sourceAddressOffset = 8
    static let destinationAddressOffset = 24
    
    var data: Data
    
    init?(_ data: Data) {
        if data.count < IPv6Packet.numFirstHeaderBytes {
            NSLog("Invalid IPv6 Packet size \(data.count)")
            return nil
        }
        
        self.data = data
        
        super.init()
        
        let minLen = Int(self.payloadLength) + IPv6Packet.numFirstHeaderBytes
        if minLen > data.count {
            NSLog("Invalid IPv6 Packet length=\(minLen), buffer size=\(data.count)")
            return nil
        }
    }
    
    init?(count:Int) {
        if (count < IPv6Packet.numFirstHeaderBytes) {
            NSLog("Invalid IPv6 Packet size \(count)")
            return nil
        }
        
        self.data = Data(count: count)
        
        super.init()
        self.version = IPv6Packet.version6
    }
    
    var version:UInt8 {
        get { return data[IPv6Packet.versionOffset] >> 4 }
        set {
            data[IPv6Packet.versionOffset] =
                (newValue << 4) | (data[IPv6Packet.versionOffset] & 0x0f)
        }
    }
    
    // includes any extension headers...
    var payloadLength:UInt16 {
        get { return IPUtils.extractUInt16(data, from: IPv6Packet.payloadLengthOffset) }
        set {
            IPUtils.updateUInt16(&data, at: IPv6Packet.payloadLengthOffset, value: newValue)
        }
    }
    
    var nextHeader:IPv6NextHeader {
        get { return IPv6NextHeader(data[IPv6Packet.nextHeaderOffet]) }
        set { data[IPv6Packet.nextHeaderOffet] = newValue.rawValue }
    }
    
    var hopLimit:UInt8 {
        get { return data[IPv6Packet.hopLimitOffset] }
        set { data[IPv6Packet.hopLimitOffset] = newValue }
    }
    
    // Need to calculate location based on any extension headers
    var protocolId: IPProtocolId {
        get {
            // TODO: Need to calculate location based on any extension headers
            if self.nextHeader.isExtensionHeader() {
                NSLog("************ EXTENSION HEADER!!! *****************")
            }
            
            switch self.nextHeader {
            case .TCP: return IPProtocolId.TCP
            case .UDP: return IPProtocolId.UDP
            default: return IPProtocolId.other
            }
        }
    }
    
    var sourceAddress : Data {
        get { return data[IPv6Packet.sourceAddressOffset...(IPv6Packet.sourceAddressOffset+15)] }
        set {
            data.replaceSubrange(
                IPv6Packet.sourceAddressOffset...(IPv6Packet.sourceAddressOffset+15),
                with: newValue)
        }
    }
    
    var destinationAddress : Data {
        get { return data[IPv6Packet.destinationAddressOffset...(IPv6Packet.destinationAddressOffset+15)] }
        set {
            data.replaceSubrange(
                IPv6Packet.destinationAddressOffset...(IPv6Packet.destinationAddressOffset+15),
                with: newValue)
        }
    }
    
    var sourceAddressString: String {
        get { return IPUtils.ipV6AddressToSting(sourceAddress) }
    }
    
    var destinationAddressString: String {
        get { return IPUtils.ipV6AddressToSting(destinationAddress) }
    }
    
    var payload:Data? {
        // TODO: handle (skip) extension headers...
        get {
            let startIndx = Int(IPv6Packet.numFirstHeaderBytes)
            if (startIndx >= self.data.count) {
                return nil
            }
            return self.data[startIndx...]
        }
        
        set {
            let startIndx = Int(IPv6Packet.numFirstHeaderBytes)
            if let nv = newValue {
                if startIndx < self.data.count {
                    self.data.replaceSubrange(startIndx..., with:nv)
                } else {
                    self.data.append(nv)
                }
            } else if startIndx < self.data.count {
                self.data.removeSubrange(startIndx...)
            }
            self.updateLengthsAndChecksums()
        }
    }
    
    func createFromRefPacket(_ refPacket: IPPacket) -> IPPacket {
        let ip = IPv6Packet(count:(IPv6Packet.numFirstHeaderBytes))!
        ip.version = IPv6Packet.version6
        ip.nextHeader = IPv6NextHeader(refPacket.protocolId.rawValue)
        ip.hopLimit = IPv6Packet.defaultHopLimit
        ip.sourceAddress = refPacket.destinationAddress
        ip.destinationAddress = refPacket.sourceAddress
        return ip
    }
    
    func updateLengthsAndChecksums() {
        self.payloadLength = UInt16(self.data.count - IPv6Packet.numFirstHeaderBytes)
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(version), Src: \(sourceAddressString), Dest:\(destinationAddressString)\n"
        
        s += "\n" +
            "   version: \(version)\n" +
            "   payloadLength: \(payloadLength)\n" +
            "   nextHeader: \(nextHeader)\n" +
            "   hopLimit: \(hopLimit)" +
            "   sourceAddress: \(sourceAddressString)\n" +
            "   destinationAddress: \(destinationAddressString)\n"
        
        if let payload = self.payload {
            s += IPUtils.payloadToString(payload)
        }
        return s
    }
}
