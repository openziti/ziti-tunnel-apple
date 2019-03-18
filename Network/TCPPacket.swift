//
//  TCPPacket.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/18/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class TCPPacket : NSObject {
    static let minHeaderBytes = 20
    static let sourePortOffset = 0
    static let destinationPortOffset = 2
    static let sequenceNumberOffset = 4
    static let acknowledgmentNumberOffset = 8
    static let dataOffsetOffset = 12
    static let flagsOffset = 13
    static let windowSizeOffset = 14
    static let checksumOffset = 16
    static let urgentPointerOffset = 18
    static let optionsOffset = 20
    var ip:IPPacket
    
    
    init?(_ ipPacket:IPPacket) {
        self.ip = ipPacket
        super.init()
        guard ipPacket.protocolId == IPProtocolId.TCP else { return nil }
        guard let ipPayload = self.ip.payload else { return nil }
        guard ipPayload.count >= TCPPacket.minHeaderBytes else { return nil }
    }
    
    init(_ refPacket:UDPPacket, payload:Data?) {
        self.ip = refPacket.ip.createFromRefPacket(refPacket.ip)
        super.init()
        self.sourcePort = refPacket.destinationPort
        self.destinationPort = refPacket.sourcePort
        self.payload = payload
    }
    
    var numHeaderBytes:Int { return Int(dataOffset * 4) }
    
    var sourcePort:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, TCPPacket.sourePortOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, TCPPacket.sourePortOffset, newValue) }
    }
    
    var destinationPort:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, TCPPacket.destinationPortOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, TCPPacket.destinationPortOffset, newValue) }
    }
    
    var sequenceNumber:UInt32 {
        get { return IPUtils.UInt32FromPayload(self.ip.payload, TCPPacket.sequenceNumberOffset) }
        set { IPUtils.UInt32ToPayload(self.ip.payload, &ip.data, TCPPacket.sequenceNumberOffset, newValue) }
    }
    
    var acknowledgmentNumber:UInt32 {
        get { return IPUtils.UInt32FromPayload(self.ip.payload, TCPPacket.acknowledgmentNumberOffset) }
        set { IPUtils.UInt32ToPayload(self.ip.payload, &ip.data, TCPPacket.acknowledgmentNumberOffset, newValue) }
    }
    
    var dataOffset:UInt8 {
        get {
            if let ipPayload = self.ip.payload {
                return ip.data[ipPayload.startIndex + TCPPacket.dataOffsetOffset] >> 4
            }
            return 0
        }
        set {
            if let ipPayload = self.ip.payload {
                let offset = ipPayload.startIndex + TCPPacket.dataOffsetOffset
                ip.data[offset + TCPPacket.dataOffsetOffset] =
                    (newValue << 4) | (ip.data[offset + TCPPacket.dataOffsetOffset] & 0x0f)
            }
        }
    }
    
    // ignore ns bit (experimental)
    var flags:UInt8 {
        get { return IPUtils.UInt8FromPayload(self.ip.payload, TCPPacket.flagsOffset) }
        set { IPUtils.UInt8ToPayload(self.ip.payload, &ip.data, TCPPacket.flagsOffset, newValue) }
    }
    
    func isBitSet(_ bits:UInt8, _ bit:UInt8) -> Bool {
        return ((bits >> bit) & 0x01) == 0x01
    }
    
    func setBit(_ bits: inout UInt8, _ bit:UInt8, _ val:Bool) {
        let mask = (0x80 >> (7 - bit))
        if val { bits = bits | mask }
        else { bits = bits & ~mask }
    }
    
    var CWR:Bool {
        get { return isBitSet(flags, 7) }
        set {
            var bits = self.flags
            setBit(&bits, 7, newValue)
            self.flags = bits
        }
    }
    
    var ECE:Bool {
        get { return isBitSet(flags, 6) }
        set {
            var bits = self.flags
            setBit(&bits, 6, newValue)
            self.flags = bits
        }
    }
    
    var URG:Bool {
        get { return isBitSet(flags, 5) }
        set {
            var bits = self.flags
            setBit(&bits, 5, newValue)
            self.flags = bits
        }
    }
    
    var ACK:Bool {
        get { return isBitSet(flags, 4) }
        set {
            var bits = self.flags
            setBit(&bits, 4, newValue)
            self.flags = bits
        }
    }
    
    var PSH:Bool {
        get { return isBitSet(flags, 3) }
        set {
            var bits = self.flags
            setBit(&bits, 3, newValue)
            self.flags = bits
        }
    }
    
    var RST:Bool {
        get { return isBitSet(flags, 2) }
        set {
            var bits = self.flags
            setBit(&bits, 2, newValue)
            self.flags = bits
        }
    }
    
    var SYN:Bool {
        get { return isBitSet(flags, 1) }
        set {
            var bits = self.flags
            setBit(&bits, 1, newValue)
            self.flags = bits
        }
    }
    
    var FIN:Bool {
        get { return isBitSet(flags, 0) }
        set {
            var bits = self.flags
            setBit(&bits, 0, newValue)
            self.flags = bits
        }
    }
    
    var windowSize:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, TCPPacket.windowSizeOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, TCPPacket.windowSizeOffset, newValue) }
    }
    
    var checksum:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, TCPPacket.checksumOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, TCPPacket.checksumOffset, newValue) }
    }
    
    var urgentPointer:UInt16 {
        get { return IPUtils.UInt16FromPayload(self.ip.payload, TCPPacket.urgentPointerOffset) }
        set { IPUtils.UInt16ToPayload(self.ip.payload, &ip.data, TCPPacket.urgentPointerOffset, newValue) }
    }
    
    var payload:Data? {
        get {
            if let ipPayload = self.ip.payload {
                if ipPayload.count > self.numHeaderBytes {
                    return ipPayload[(ipPayload.startIndex + self.numHeaderBytes)...]
                }
            }
            return nil
        }
        
        set {
            var header = Data(count:self.numHeaderBytes)
            if let ipPayload = self.ip.payload {
                if ipPayload.count >= self.numHeaderBytes {
                    header = ipPayload[ipPayload.startIndex..<(ipPayload.startIndex + self.numHeaderBytes)]
                }
            }
            
            self.ip.payload = nil
            if var nv = newValue {
                nv.insert(contentsOf:header, at:nv.startIndex)
                self.ip.payload = nv
            } else {
                self.ip.payload = header
            }
        }
    }
    
    func updateLengthsAndChecksums() {
        // TODO: add my own checksum
        self.ip.updateLengthsAndChecksums()
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(ip.version), Src: \(ip.sourceAddressString), Dest:\(ip.destinationAddressString)\n"
        s += "Tramsmission Control Protocol, Src Port: \(sourcePort), Dst Port: \(destinationPort), Seq: \(sequenceNumber)\n"
        s += "   Sequence number: \(sequenceNumber)\n"
        s += "   Acknowledgement number: \(acknowledgmentNumber)\n"
        s += "   Header Length: \(numHeaderBytes) bytes\n"
        s += "   Flags: \(String(format:"0x%2x", UInt16(flags)))\n"
        s += "      CWR: \(CWR)\n"
        s += "      ECE: \(ECE)\n"
        s += "      URG: \(URG)\n"
        s += "      ACK: \(ACK)\n"
        s += "      PSH: \(PSH)\n"
        s += "      SYN: \(SYN)\n"
        s += "      FIN: \(FIN)\n"
        s += "   Window size value: \(windowSize)\n"
        s += "   Checksum: \(String(format:"0x%2x", checksum))\n"
        s += "   Options: \("todo")\n"
        if let payload = self.payload {
            s += IPUtils.payloadToString(payload)
        }
        return s;
    }
}
