//
//  UDPPacket.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

class UDPPacket : NSObject {
    var ip:IPv4Packet
    
    init?(_ ipPacket:IPv4Packet) {
        self.ip = ipPacket
        if (ipPacket.protocolId != UInt8(IPPROTO_UDP)) {
            NSLog("Invalid UDP Packet, protocol=\(ipPacket.protocolString)")
            return nil
        }
        
        super.init()
        
        if let ipPayload = self.ip.payload {
            if ipPayload.count < 8 {
                NSLog("Invalid UDP Packet size \(ipPayload.count)")
                return nil
            }
            
            if self.length > ipPayload.count {
                NSLog("Invalid UDP Packet length=\(self.length), buffer size=\(ipPayload.count)")
                return nil
            }
        } else {
            NSLog("Invalid (nil) IP Payload for UDP Packet")
            return nil
        }
    }
    
    init(_ refPacket:UDPPacket, payload:Data?) {
        self.ip = IPv4Packet(count:28)!
        self.ip.version = 4
        self.ip.headerLength = 5
        self.ip.identification = ip.genIdentificationNumber()
        self.ip.flags = IPv4Flags.dontFragment
        self.ip.ttl = 255
        self.ip.protocolId = UInt8(IPPROTO_UDP)
        self.ip.sourceAddress = refPacket.ip.destinationAddress
        self.ip.destinationAddress = refPacket.ip.sourceAddress
        
        super.init()

        self.sourcePort = refPacket.destinationPort
        self.destinationPort = refPacket.sourcePort
        self.payload = payload
        
        if let ipPayload = ip.payload {
            self.length = UInt16(ipPayload.count)
        } else {
            self.length = 8
        }
        
        self.ip.updateHeaderChecksum()
    }
    
    var sourcePort:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPv4Utils.extractUInt16(ipPayload, from: ipPayload.startIndex)
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                IPv4Utils.updateUInt16(&ip.data, at: ipPayload.startIndex, value: newValue)
            }
        }
    }
    
    var destinationPort:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPv4Utils.extractUInt16(ipPayload, from: ipPayload.startIndex+2)
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                IPv4Utils.updateUInt16(&ip.data, at: ipPayload.startIndex+2, value: newValue)
            }
        }
    }
    
    var length:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPv4Utils.extractUInt16(ipPayload, from: ipPayload.startIndex+4)
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                IPv4Utils.updateUInt16(&ip.data, at: ipPayload.startIndex+4, value: newValue)
            }
        }
    }
    
    var checksum:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPv4Utils.extractUInt16(ipPayload, from: ipPayload.startIndex+6)
            }
            return 0
        }
        
        set {
            if let ipPayload = self.ip.payload {
                IPv4Utils.updateUInt16(&ip.data, at: ipPayload.startIndex+6, value: newValue)
            }
        }
    }
    
    var payload:Data? {
        get {
            if let ipPayload = self.ip.payload {
                if ipPayload.count > 8 {
                    return ipPayload[(ipPayload.startIndex+8)...]
                }
            }
            return nil
        }
        
        set {
            var header = Data(count:8)
            if let ipPayload = self.ip.payload {
                if ipPayload.count >= 8 {
                    header = ipPayload[ipPayload.startIndex..<(ipPayload.startIndex+8)]
                }
            }
            
            self.ip.payload = nil
            if var nv = newValue {
                nv.insert(contentsOf:header, at:nv.startIndex)
                self.ip.payload = nv
                self.length = UInt16(nv.count)
            } else {
                self.ip.payload = header
                self.length = UInt16(header.count)
            }
        }
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(self.ip.version), Src: \(self.ip.sourceAddressString), Dest:\(self.ip.destinationAddressString)\n"
        
        s += "User Datagram Protocol, Src Port: \(self.sourcePort), Dst Port: \(self.destinationPort)\n"
        s += "   Length: \(self.length)\n"
        s += "   Checksum: \(String(format:"0x%2x", self.checksum))\n"
        
        if let payload = self.payload {
            s += IPv4Utils.payloadToString(payload)
        }
        return s;
    }
}
