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
        super.init()
        guard ipPacket.protocolId == IPProtocolId.UDP else { return nil }
        guard let ipPayload = self.ip.payload else { return nil }
        guard ipPayload.count >= UDPPacket.numHeaderBytes else { return nil }
        guard self.length <= ipPayload.count else { return nil }
    }
    
    init(_ refPacket:UDPPacket, payload:Data?) {
        self.ip = refPacket.ip.createFromRefPacket(refPacket.ip)
        super.init()
        self.payload = payload
        self.sourcePort = refPacket.destinationPort
        self.destinationPort = refPacket.sourcePort
        
        if let ipPayload = ip.payload {
            self.length = UInt16(ipPayload.count)
        } else {
            self.length = UInt16(UDPPacket.numHeaderBytes)
        }        
    }
    
    var sourcePort:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, UDPPacket.sourePortOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, UDPPacket.sourePortOffset, newValue) }
    }
    
    var destinationPort:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, UDPPacket.destinationPortOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data,
                                      UDPPacket.destinationPortOffset, newValue) }
    }
    
    var length:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, UDPPacket.lengthOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, UDPPacket.lengthOffset, newValue) }
    }
    
    var checksum:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, UDPPacket.checksumOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, UDPPacket.checksumOffset, newValue) }
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
