//
//  UDPPacket.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

class UDPPacket : NSObject {
    
    static let numHeaderBytes = 8
    static let sourePortOffset = 0
    static let destinationPortOffset = 2
    static let lengthOffset = 4
    static let checksumOffset = 6
    
    var ip:IPPacket
    
    init?(_ ipPacket:IPPacket) {
        self.ip = ipPacket
        if (ipPacket.protocolId != IPProtocolId.UDP) {
            NSLog("Invalid UDP Packet, protocol=\(ipPacket.protocolId)")
            return nil
        }
        
        super.init()
        
        if let ipPayload = self.ip.payload {
            if ipPayload.count < UDPPacket.numHeaderBytes {
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
        
        self.ip = refPacket.ip.createFromRefPacket(refPacket.ip)
        
        super.init()

        self.sourcePort = refPacket.destinationPort
        self.destinationPort = refPacket.sourcePort
        self.payload = payload
        
        if let ipPayload = ip.payload {
            self.length = UInt16(ipPayload.count)
        } else {
            self.length = UInt16(UDPPacket.numHeaderBytes)
        }        
    }
    
    var sourcePort:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPUtils.extractUInt16(ipPayload,
                                               from: ipPayload.startIndex + UDPPacket.sourePortOffset)
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                IPUtils.updateUInt16(&ip.data,
                                       at: ipPayload.startIndex + UDPPacket.sourePortOffset,
                                       value: newValue)
            }
        }
    }
    
    var destinationPort:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPUtils.extractUInt16(ipPayload,
                                               from: ipPayload.startIndex + UDPPacket.destinationPortOffset)
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                IPUtils.updateUInt16(&ip.data,
                                       at: ipPayload.startIndex + UDPPacket.destinationPortOffset,
                                       value: newValue)
            }
        }
    }
    
    var length:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPUtils.extractUInt16(ipPayload,
                                               from: ipPayload.startIndex + UDPPacket.lengthOffset)
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                IPUtils.updateUInt16(&ip.data,
                                       at: ipPayload.startIndex + UDPPacket.lengthOffset,
                                       value: newValue)
            }
        }
    }
    
    var checksum:UInt16 {
        get {
            if let ipPayload = self.ip.payload {
                return IPUtils.extractUInt16(ipPayload,
                                               from: ipPayload.startIndex + UDPPacket.checksumOffset)
            }
            return 0
        }
        
        set {
            if let ipPayload = self.ip.payload {
                IPUtils.updateUInt16(&ip.data,
                                       at: ipPayload.startIndex + UDPPacket.checksumOffset,
                                       value: newValue)
            }
        }
    }
    
    var payload:Data? {
        get {
            if let ipPayload = self.ip.payload {
                if ipPayload.count > UDPPacket.numHeaderBytes {
                    return ipPayload[(ipPayload.startIndex + UDPPacket.numHeaderBytes)...]
                }
            }
            return nil
        }
        
        set {
            var header = Data(count:UDPPacket.numHeaderBytes)
            if let ipPayload = self.ip.payload {
                if ipPayload.count >= UDPPacket.numHeaderBytes {
                    header = ipPayload[ipPayload.startIndex..<(ipPayload.startIndex + UDPPacket.numHeaderBytes)]
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
    
    func updateLengthsAndChecksums() {
        if let ipPayload = self.ip.payload {
            self.length = UInt16(ipPayload.count)
        }
        self.ip.updateLengthsAndChecksums()
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(self.ip.version), Src: \(self.ip.sourceAddressString), Dest:\(self.ip.destinationAddressString)\n"
        
        s += "User Datagram Protocol, Src Port: \(self.sourcePort), Dst Port: \(self.destinationPort)\n"
        s += "   Length: \(self.length)\n"
        s += "   Checksum: \(String(format:"0x%2x", self.checksum))\n"
        
        if let payload = self.payload {
            s += IPUtils.payloadToString(payload)
        }
        return s;
    }
}
