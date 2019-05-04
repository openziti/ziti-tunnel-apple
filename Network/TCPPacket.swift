//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

enum TCPOptionKind : UInt8 {
    case eol = 0
    case nop
    case mss
    case windowScale
    case sacAllowed
    case sac
    case times = 8
    case unrecognized
    
    init(_ byte:UInt8) {
        let responseCode = byte
        
        switch responseCode {
        case 0: self = .eol
        case 1: self = .nop
        case 2: self = .mss
        case 3: self = .windowScale
        case 4: self = .sacAllowed
        case 5: self = .sac
        case 8: self = .times
        default: self = .unrecognized
        }
    }
}

class TCPOption : NSObject {
    var kind:TCPOptionKind = .nop
    var len:UInt8?
    var data:Data?
    
    init?(_ bytes:Data) {
        guard bytes.count > 0 else {
            return nil
        }
        super.init()
        
        let i = bytes.startIndex
        kind = TCPOptionKind(bytes[i])
        if kind == .eol || kind == .nop {
            len = nil
            data = nil
        } else {
            if bytes.count > 1 {
                len = bytes[i+1]
                if let len = len, len > 2 {
                    data = bytes.subdata(in: i+2..<(i + Int(len)))
                }
            }
        }
    }
    
    override var debugDescription: String {
        return "      \(kind) len:\(len ?? 0)\n"
    }
}

class TCPOptionMss : TCPOption {
    var mss:UInt16 {
        get {
            if let data = data {
                return IPUtils.extractUInt16(data, from: data.startIndex)
            }
            return 0
        }
        set {
            if var data = data {
                IPUtils.updateUInt16(&data, at: data.startIndex, value: newValue)
            }
        }
    }
    
    init?(_ mss:UInt16) {
        var bytes = Data()
        bytes.append(TCPOptionKind.mss.rawValue)
        bytes.append(0x04)
        IPUtils.appendUInt16(&bytes, value: mss)
        super.init(bytes)
    }
    
    override init?(_ bytes:Data) {
        super.init(bytes)
        guard kind == .mss, len == 4 else {
            return nil
        }
    }
    
    override var debugDescription: String {
        return "      .mss: \(mss)\n"
    }
}

class TCPOptionWindowScale : TCPOption {
    var scale:UInt8 {
        get {
            if let data = data {
                return data[data.startIndex]
            }
            return 0
        }
        set {
            if var data = data {
                data[data.startIndex] = newValue
            }
        }
    }
    
    init?(_ scale:UInt8) {
        var bytes = Data()
        bytes.append(TCPOptionKind.windowScale.rawValue)
        bytes.append(0x03)
        bytes.append(scale)
        super.init(bytes)
    }
    
    override init?(_ bytes:Data) {
        super.init(bytes)
        guard kind == .windowScale, len == 3 else {
            return nil
        }
    }
    
    override var debugDescription: String {
        return "      .windowsScale: \(scale) (multiply by \(1<<scale))\n"
    }
}

class TCPOptions : NSObject {
    var options:[TCPOption] = []
    
    init(_ bytes:Data) {
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let opt:TCPOption?
            switch TCPOptionKind(bytes[i]) {
                case .mss: opt = TCPOptionMss(bytes[i...])
                case .windowScale: opt = TCPOptionWindowScale(bytes[i...])
                default: opt = TCPOption(bytes[i...])
            }
            if opt == nil {
                break
            } else {
                if opt!.kind == .eol { break }
                options.append(opt!)
                i += (opt!.len ?? 0 > 0) ? Int(opt!.len!) : 1
            }
        }
    }
    
    init(_ options:[TCPOption]?) {
        guard let options = options else {
            self.options = []
            return
        }
        self.options = options
    }
    
    func encode() -> Data? {
        var data = Data()
        options.forEach { opt in
            data.append(opt.kind.rawValue)
            if let len = opt.len {
                data.append(len)
                if let optData = opt.data {
                    let min = optData.startIndex
                    let max = optData.startIndex + (Int(len) - 2)
                    data.append(optData[min..<max])
                }
            }
        }
        
        // pad to 4 byte boundry
        let remaining = data.count % 4
        if remaining != 0 {
            data.append(Data(count:remaining))
        }
        return data.count > 0 ? data : nil
    }
    
    override var debugDescription: String {
        var s = ""
        options.forEach { opt in
            s += opt.debugDescription
        }
        return s
    }
}

enum TCPFlags : UInt8 {
    case FIN = 1
    case SYN = 2
    case RST = 4
    case PSH = 8
    case ACK = 16
    case URG = 32
}

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
    
    init?(_ ipPacket:IPPacket, options:[TCPOption]?, payload:Data?) {
        self.ip = ipPacket
        super.init()
        guard let ipPayload = self.ip.payload else { return nil }
        guard ipPayload.count >= TCPPacket.minHeaderBytes else { return nil }
        self.ip.protocolId = IPProtocolId.TCP
        self.dataOffset = 5
        self.payload = payload
        self.options = (options?.count ?? 0 > 0) ? TCPOptions(options) : nil
    }
    
    init(refPacket:TCPPacket, options:[TCPOption]?, payload:Data?) {
        self.ip = refPacket.ip.createFromRefPacket(refPacket.ip)
        super.init()
        self.payload = payload
        self.options = (options?.count ?? 0 > 0) ? TCPOptions(options) : nil
        self.sourcePort = refPacket.destinationPort
        self.destinationPort = refPacket.sourcePort
        self.flags = 0
        self.sequenceNumber = 0
        self.acknowledgmentNumber = 0
    }
    
    var options:TCPOptions? {
        get {
            if numHeaderBytes > TCPPacket.minHeaderBytes, let ipPayload = self.ip.payload {
                let min = ipPayload.startIndex + TCPPacket.minHeaderBytes
                let max = min + (Int(dataOffset) - 5) * 4
                return TCPOptions(ipPayload[min..<max])
            }
            return nil
        }
        set {
            if let ipPayload = self.ip.payload {
                // remove whatever is there
                let min = ipPayload.startIndex + TCPPacket.minHeaderBytes
                let max = min + (Int(dataOffset) - 5) * 4
                if min < max {
                    ip.data.removeSubrange(min..<max)
                }
                
                // insert new options
                let data = newValue?.encode()
                let newNumBytes = data?.count ?? 0
                if newNumBytes > 0 {
                    ip.data.insert(contentsOf: data!, at: ipPayload.startIndex + TCPPacket.minHeaderBytes)
                }
                dataOffset = UInt8(5 + (newNumBytes > 0 ? Int(newNumBytes / 4) : 0))
            }
        }
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
                ip.data[offset] = (newValue << 4) | (ip.data[offset] & 0x0f)
            }
        }
    }
    
    // ignore ns bit (experimental)
    var flags:UInt8 {
        get { return IPUtils.UInt8FromPayload(self.ip.payload, TCPPacket.flagsOffset) }
        set { IPUtils.UInt8ToPayload(self.ip.payload, &ip.data, TCPPacket.flagsOffset, newValue) }
    }
    
    func hasFlags(_ flags:UInt8) -> Bool {
        return (self.flags & flags) == flags
    }
    
    var CWR:Bool {
        get { return IPUtils.isBitSet(flags, 7) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 7, newValue)
            self.flags = bits
        }
    }
    
    var ECE:Bool {
        get { return IPUtils.isBitSet(flags, 6) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 6, newValue)
            self.flags = bits
        }
    }
    
    var URG:Bool {
        get { return IPUtils.isBitSet(flags, 5) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 5, newValue)
            self.flags = bits
        }
    }
    
    var ACK:Bool {
        get { return IPUtils.isBitSet(flags, 4) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 4, newValue)
            self.flags = bits
        }
    }
    
    var PSH:Bool {
        get { return IPUtils.isBitSet(flags, 3) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 3, newValue)
            self.flags = bits
        }
    }
    
    var RST:Bool {
        get { return IPUtils.isBitSet(flags, 2) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 2, newValue)
            self.flags = bits
        }
    }
    
    var SYN:Bool {
        get { return IPUtils.isBitSet(flags, 1) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 1, newValue)
            self.flags = bits
        }
    }
    
    var FIN:Bool {
        get { return IPUtils.isBitSet(flags, 0) }
        set {
            var bits = self.flags
            IPUtils.setBit(&bits, 0, newValue)
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
            var header = Data(count:TCPPacket.minHeaderBytes)
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
    
    func computeChecksum() -> UInt16 {
        var psuedo = Data()
        psuedo.append(ip.sourceAddress)
        psuedo.append(ip.destinationAddress)
        psuedo.append(contentsOf: [0x00, 0x06]) // TCP
        IPUtils.appendUInt16(&psuedo, value: UInt16(ip.payload?.count ?? 0))
        
        let hdrSize = psuedo.count
        if let ipPayload = ip.payload {
            psuedo.append(ipPayload)
        }
        
        if (psuedo.count % 2) != 0 {
            let lastWord = UInt16(psuedo[psuedo.count-1])
            IPUtils.appendUInt16(&psuedo, value: lastWord)
        }
        
        var ui16Array:[UInt16] = psuedo[..<psuedo.count].withUnsafeBytes{ urbp in
            urbp.bindMemory(to: UInt16.self).map(UInt16.init(bigEndian:))
        }
        
        // zero out checksum
        ui16Array[hdrSize/2 + TCPPacket.checksumOffset/2] = 0x0000
        
        return IPUtils.computeChecksum(ui16Array)
    }
    
    func updateLengthsAndChecksums() {
        self.checksum = computeChecksum()
        self.ip.updateLengthsAndChecksums()
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(ip.version), Src: \(ip.sourceAddressString), Dest:\(ip.destinationAddressString)\n"
        s += "Tramsmission Control Protocol, Src Port: \(sourcePort), Dst Port: \(destinationPort), Seq: \(sequenceNumber)\n"
        s += "   Sequence number: \(sequenceNumber)\n"
        s += "   Acknowledgement number: \(acknowledgmentNumber)\n"
        s += "   Header Length: \(numHeaderBytes) bytes\n"
        s += "   Flags: \(String(format:"0x%2x", UInt16(flags))) "
        s += CWR ? " CWR" : ""
        s += ECE ? " ECE" : ""
        s += URG ? " URG" : ""
        s += ACK ? " ACK" : ""
        s += PSH ? " PSH" : ""
        s += SYN ? " SYN" : ""
        s += FIN ? " FIN" : ""
        s += "\n"
        s += "   Window size value: \(windowSize)\n"
        s += "   Checksum: \(String(format:"0x%2x", checksum))\n"
        s += "   Computed checksun: \(String(format:"0x%2x", computeChecksum()))\n"
        s += "   Options: \(options?.options.count ?? 0)\n"
        if let options = options {
            s += options.debugDescription
        }
        
        if let payload = self.payload {
            let max = payload.startIndex + (payload.count < 1000 ? payload.count : 1000)
            s += IPUtils.payloadToString(payload.subdata(in: payload.startIndex..<max))
        }
        return s;
    }
}
