//
//  DNSPacket.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/20/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

enum DNSOpCode : UInt8 {
    case query
    case nQuery
    case status
    case notify
    case update
    case unrecognized
    
    init(_ byte:UInt8) {
        let opCode = (byte >> 3) & 0x0f
        
        switch opCode {
        case 0: self = .query
        case 1: self = .nQuery
        case 2: self = .status
        case 3: self = .notify
        case 4: self = .update
        default: self = .unrecognized
        }
    }
}

enum DNSResponseCode : UInt8 {
    case noError
    case formatError
    case serverFailure
    case nameError
    case notImplemented
    case refused
    case yxDomein
    case yxRRSet
    case nxRRSet
    case notAuth
    case notZone
    case unrecognized
    
    init(_ byte:UInt8) {
        let responseCode = byte & 0x0f
        
        switch responseCode {
        case 0: self = .noError
        case 1: self = .formatError
        case 2: self = .serverFailure
        case 3: self = .nameError
        case 4: self = .notImplemented
        case 5: self = .refused
        case 6: self = .yxDomein
        case 7: self = .yxRRSet
        case 8: self = .nxRRSet
        case 9: self = .notAuth
        case 10: self = .notZone
        default: self = .unrecognized
        }
    }
}

enum DNSRecordType : UInt16 {
    case A = 1
    case NS = 2
    case CNAME = 5
    case SOA = 6
    case PTR = 12
    case MX = 15
    case TXT = 16
    case AAAA = 28
    case unrecognized
    
    init(_ data:UInt16) {
        switch data {
        case 1: self = .A
        case 2: self = .NS
        case 5: self = .CNAME
        case 6: self = .SOA
        case 12: self = .PTR
        case 15: self = .MX
        case 16: self = .TXT
        case 28: self = .AAAA
        default: self = .unrecognized
        }
    }
}

enum DNSRecordClass : UInt16 {
    case IN = 1
    case unrecognized
    
    init(_ data:UInt16) {
        switch data {
        case 1: self = .IN
        default: self = .unrecognized
        }
    }
}

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
            offset = Int(IPv4Utils.extractUInt16(data, from: data.startIndex + offset) & 0x3f)
            return findCountAndOffset(data, offset:&offset)
        } else {
            return Int(countOrOffset)
        }
    }
}

typealias DNSQuestion = DNSResoureRecodeBase

class DNSResoureRecodeBase : NSObject {
    
    static let minNumBytes = 5
    
    let name:DNSName
    let recordType:DNSRecordType
    let recordClass:DNSRecordClass
    var numBytes = 0
    
    init?(_ data:Data, offset:Int) {
        
        if data.count < DNSQuestion.minNumBytes {
            NSLog("Invalid data for DNS Question")
            return nil
        }
        
        self.name = DNSName(data, offset:offset)
        
        let rTypeIndx = data.startIndex + self.name.numBytes
        self.recordType = DNSRecordType(IPv4Utils.extractUInt16(data, from: rTypeIndx))
        self.recordClass = DNSRecordClass(IPv4Utils.extractUInt16(data, from: rTypeIndx + MemoryLayout<UInt16>.size))
        self.numBytes = self.name.numBytes + (MemoryLayout<UInt16>.size * 2)
    }
    
    init(_ nameString:String, recordType:DNSRecordType, recordClass:DNSRecordClass) {
        self.name = DNSName(nameString)
        self.recordType = recordType
        self.recordClass = recordClass
        self.numBytes = self.name.numBytes + (MemoryLayout<UInt16>.size * 2)
    }
    
    func toBytes() -> Data {
        var data = Data()
        
        let segments:[String] = self.name.nameString.components(separatedBy: ".")
        segments.forEach { seg in
            data.append(UInt8(seg.count))
            data.append(contentsOf:seg.utf8)
        }
        data.append(0x00)
        IPv4Utils.appendUInt16(&data, value: self.recordType.rawValue)
        IPv4Utils.appendUInt16(&data, value: self.recordClass.rawValue)

        return data
    }
    
    override var debugDescription: String {
        return "   > " + self.name.nameString + " type: \(self.recordType), class \(self.recordClass)\n"
    }
}

class DNSResourceRecord : DNSResoureRecodeBase {
    
    var ttl:UInt32 = 0
    var resourceDataLength:UInt16 = 0
    var resourceData:Data? = nil
    
    override init?(_ data:Data, offset:Int) {
        super.init(data, offset:offset)
        
        var indx = data.startIndex + offset + self.numBytes
        
        self.ttl = IPv4Utils.extractUInt32(data, from: indx)
        self.numBytes += MemoryLayout<UInt32>.size
        indx += MemoryLayout<UInt32>.size
        
        self.resourceDataLength = IPv4Utils.extractUInt16(data, from: indx)
        self.numBytes += MemoryLayout<UInt16>.size
        indx += MemoryLayout<UInt16>.size
        
        let rdl = Int(self.resourceDataLength)
        self.resourceData = data[indx..<(indx + rdl)]
        self.numBytes += rdl
    }
    
    init(_ nameString:String, recordType:DNSRecordType, recordClass:DNSRecordClass, ttl:UInt32, resourceData:Data?) {
        super.init(nameString, recordType:recordType, recordClass:recordClass)
        self.ttl = ttl
        
        self.numBytes += MemoryLayout<UInt32>.size + MemoryLayout<UInt16>.size // ttl and recordLength
        
        if let data = resourceData {
            self.resourceData = data
            self.resourceDataLength = UInt16(data.count)
            self.numBytes += data.count
        }
    }
    
    override func toBytes() -> Data {
        var data = super.toBytes()
        IPv4Utils.appendUInt32(&data, value: self.ttl)
        IPv4Utils.appendUInt16(&data, value: self.resourceDataLength)
        
        if let rd = self.resourceData {
            data.append(rd)
        }
        return data
    }

    override var debugDescription: String {
        var s =  "   > " + self.name.nameString + " type: \(self.recordType), class \(self.recordClass)\n"
        s += "      ttl: \(self.ttl)\n"
        s += "      resourceDataLength: \(self.resourceDataLength)\n"
        
        if let data = self.resourceData {
            s += " Resource Data:\n"
            s += IPv4Utils.payloadToString(data)
        }
        return s
    }
}

class DNSPacket : NSObject {
    var udp:UDPPacket
    
    static let numHeaderBytes = 12
    
    static let idOffset = 0
    static let flagsOffset = 2
    static let responseCodeOffset = 3
    static let questionCountOffset = 4
    static let answerRecordCountOffset = 6
    static let authorityRecordCountOffset = 8
    static let additionalRecordCountOffset = 10
    static let answersOffset = 12
    
    init?(_ udp:UDPPacket) {
        self.udp = udp
        
        super.init()

        if let udpPayload = self.udp.payload {
            if udpPayload.count < UDPPacket.numHeaderBytes {
                NSLog("Invalid DNS Packet size \(udpPayload.count)")
                return nil
            }
            
            if self.questions.count < 1 {
                NSLog("Invalid DNS question count=\(self.questions.count)")
                return nil
            }
        } else {
            NSLog("Invalid (nil) UDP Payload for DNS Packet")
            return nil
        }
    }
    
    init(_ refPacket:DNSPacket, questions:[DNSQuestion]?) {
        self.udp = UDPPacket(refPacket.udp, payload:Data(count:12))
        
        super.init()
        
        self.id = refPacket.id
        self.qrFlag = true
        self.opCode = DNSOpCode.query
        self.recursionDesiredFlag = refPacket.recursionDesiredFlag
        self.responseCode = DNSResponseCode.noError
        self.questions = (questions != nil) ? questions! : []
    }
    
    var id:UInt16 {
        get {
            if let payload = udp.payload {
               return IPv4Utils.extractUInt16(payload,
                                              from: payload.startIndex + DNSPacket.idOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.idOffset,
                                       value: newValue)
            }
        }
    }
    
    var qrFlag:Bool {
        get {
            if let payload = udp.payload {
                return (payload[payload.startIndex + DNSPacket.flagsOffset] >> 7) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex + DNSPacket.flagsOffset] = (prev & 0x7f) | (byteValue << 7)
            }
        }
    }
    
    var opCode:DNSOpCode {
        get {
            if let payload = udp.payload {
                return DNSOpCode(payload[payload.startIndex + DNSPacket.flagsOffset])
            }
            return .unrecognized
        }
        
        set {
            if let payload = udp.payload {
                let prev:UInt8 = udp.ip.data[payload.startIndex + DNSPacket.flagsOffset]
                udp.ip.data[payload.startIndex + DNSPacket.flagsOffset] =
                    (prev & 0x87) | ((newValue.rawValue << 3) & 0x78)
            }
        }
    }
    
    var authoritativeAsnwerFlag:Bool {
        get {
            if let payload = udp.payload {
                return ((payload[payload.startIndex + DNSPacket.flagsOffset] >> 2) & 0x01) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex + DNSPacket.flagsOffset] = (prev & 0xfb) | (byteValue << 2)
            }
        }
    }
    
    var truncationFlag:Bool {
        get {
            if let payload = udp.payload {
                return ((payload[payload.startIndex + DNSPacket.flagsOffset] >> 1) & 0x01) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex + DNSPacket.flagsOffset]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex + DNSPacket.flagsOffset] = (prev & 0xfd) | (byteValue << 1)
            }
        }
    }
    
    var recursionDesiredFlag:Bool {
        get {
            if let payload = udp.payload {
                return (payload[payload.startIndex + DNSPacket.flagsOffset] & 0x01) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex + DNSPacket.flagsOffset] = (prev & 0xfe) | byteValue
            }
        }
    }
    
    var recursionAvailableFlag:Bool {
        get {
            if let payload = udp.payload {
                // first bit of the responseCode byte
                return (payload[payload.startIndex + DNSPacket.responseCodeOffset] >> 7) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                // first bit of responseCode byte
                let prev = udp.ip.data[payload.startIndex + DNSPacket.responseCodeOffset]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex + DNSPacket.responseCodeOffset] = (prev & 0x7f) | (byteValue << 7)
            }
        }
    }
    
    var responseCode:DNSResponseCode {
        get {
            if let payload = udp.payload {
                return DNSResponseCode(payload[payload.startIndex + DNSPacket.responseCodeOffset])
            }
            return .unrecognized
        }
        
        set {
            if let payload = udp.payload {
                let prev:UInt8 = udp.ip.data[payload.startIndex + DNSPacket.responseCodeOffset]
                udp.ip.data[payload.startIndex + DNSPacket.responseCodeOffset] =
                    (prev & 0xf0) | (newValue.rawValue & 0x0f)
            }
        }
    }
    
    var questionCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex + DNSPacket.questionCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex+DNSPacket.questionCountOffset,
                                       value: newValue)
            }
        }
    }
    
    var answerRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex + DNSPacket.answerRecordCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.answerRecordCountOffset,
                                       value: newValue)
            }
        }
    }
    
    var authorityRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex + DNSPacket.authorityRecordCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.authorityRecordCountOffset,
                                       value: newValue)
            }
        }
    }
    
    var additionalRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex + DNSPacket.additionalRecordCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.additionalRecordCountOffset,
                                       value: newValue)
            }
        }
    }
    
    private func getResourceRecords(recordStartIndx:Int, recordCount:Int) -> [DNSResourceRecord] {
        var response:[DNSResourceRecord] = []
        
        if let payload = udp.payload {
            var dnsData = payload[(payload.startIndex + recordStartIndx)...]
            var offset = 0
            
            for _ in 0..<recordCount {
                if let record = DNSResourceRecord(dnsData, offset:offset) {
                    if record.numBytes < dnsData.count {
                        offset += record.numBytes
                    }
                    response.append(record)
                }
            }
        }
        return response
    }
    
    private func setResourceRecords(_ newRecords:[DNSResourceRecord], recordStartIndx:Int, currRecordByteCount:Int ) {
        if let payload = udp.payload {
            
            let startIndx = payload.startIndex + recordStartIndx
            let endIndx = startIndx + currRecordByteCount
            let newBytes = self.recordBytes(newRecords)
            
            if (endIndx > startIndx) {
                udp.ip.data.removeSubrange(startIndx..<endIndx)
            }
            
            if newBytes.count > 0 {
                udp.ip.data.insert(contentsOf:newBytes, at: startIndx)
            }
        }
    }
    
    private func recordBytes(_ records:[DNSResourceRecord]) -> Data {
        var data = Data()
        records.forEach { r in data.append(r.toBytes()) }
        return data
    }
    
    var answerRecords:[DNSResourceRecord] {
        get {
            // answers start immediately after questions...
            let startIndx = self.questionsByteCount
            return self.getResourceRecords(
                recordStartIndx: startIndx,
                recordCount: Int(self.answerRecordCount))
        }
        
        set {
            let startIndx = self.questionsByteCount
            let currRecordByteCount = self.answerRecordsByteCount
            self.setResourceRecords(newValue,
                                    recordStartIndx: startIndx,
                                    currRecordByteCount: Int(currRecordByteCount))
            self.answerRecordCount = UInt16(newValue.count)
        }
    }
    
    var answerRecordsByteCount:Int {
        get { return answerRecords.reduce(0) { (sum,r) in return sum + r.numBytes } }
    }
    
    var authorityRecords:[DNSResourceRecord] {
        get {
            // answers start immediately after answers
            let startIndx = self.questionsByteCount + self.answerRecordsByteCount
            return self.getResourceRecords(
                recordStartIndx: startIndx,
                recordCount: Int(self.authorityRecordCount))
        }
        
        set {
            let startIndx = self.questionsByteCount + self.answerRecordsByteCount
            let currRecordByteCount = self.authorityRecordsByteCount
            self.setResourceRecords(newValue,
                                    recordStartIndx: startIndx,
                                    currRecordByteCount: Int(currRecordByteCount))
            self.authorityRecordCount = UInt16(newValue.count)
        }
    }
    
    var authorityRecordsByteCount:Int {
        get { return authorityRecords.reduce(0) { (sum,r) in return sum + r.numBytes } }
    }
    
    var additionalRecords:[DNSResourceRecord] {
        get {
            // answers start immediately after authority records
            let startIndx = self.questionsByteCount +
                Int(self.answerRecordsByteCount) +
                Int(self.authorityRecordCount)
            
            return self.getResourceRecords(
                recordStartIndx: startIndx,
                recordCount: Int(self.additionalRecordCount))
        }
        
        set {
            let startIndx = self.questionsByteCount +
                Int(self.answerRecordsByteCount) +
                Int(self.authorityRecordCount)
            
            let currRecordByteCount = self.additionalRecordsByteCount
            self.setResourceRecords(newValue,
                                    recordStartIndx: startIndx,
                                    currRecordByteCount: Int(currRecordByteCount))
            self.additionalRecordCount = UInt16(newValue.count)
        }
    }
    
    var additionalRecordsByteCount:Int {
        get { return additionalRecords.reduce(0) { (sum,r) in return sum + r.numBytes } }
    }
    
    var questions:[DNSQuestion] {
        get {
            var response:[DNSQuestion] = []
            if let payload = udp.payload {
                var dnsData = payload[(payload.startIndex + DNSPacket.answersOffset)...]
                var offset = 0
                
                for _ in 0..<self.questionCount {
                    if let question = DNSQuestion(dnsData, offset:offset) {
                        if question.numBytes < dnsData.count {
                            offset += question.numBytes
                        }
                        response.append(question)
                    }
                }
            }
            return response
        }
        set {
            if let payload = udp.payload {
                
                let startIndx = payload.startIndex + DNSPacket.answersOffset
                let endIndx = startIndx + self.questionsByteCount
                let newBytes = self.questionsBytes(newValue)
                
                if (endIndx > startIndx) {
                    udp.ip.data.removeSubrange(startIndx..<endIndx)
                }
                
                if newBytes.count > 0 {
                    udp.ip.data.insert(contentsOf:newBytes, at: startIndx)
                }
            }
            self.questionCount = UInt16(newValue.count)
        }
    }
    
    var questionsByteCount:Int {
        get { return questions.reduce(0) { (sum,q) in return sum + q.numBytes } }
    }
    
    func questionsBytes(_ questions:[DNSQuestion]) -> Data {
        var data = Data()
        questions.forEach { q in data.append(q.toBytes()) }
        return data
    }
    
    override var debugDescription: String {
        var s:String = "IPv\(self.udp.ip.version), Src: \(self.udp.ip.sourceAddressString), Dest:\(self.udp.ip.destinationAddressString)\n"
        
        s += "User Datagram Protocol, Src Port: \(self.udp.sourcePort), Dst Port: \(self.udp.destinationPort)\n"
        s += "Domain Name Service"
        self.qrFlag ? (s += " (response)\n") : (s += " (query)\n")
        
        s += "   id: \(String(format:"0x%2x", self.id))\n"
        s += "   qrFlag: \(self.qrFlag)\n"
        s += "   opCode: \(self.opCode)\n"
        s += "   authoritativeAsnwerFlag: \(self.authoritativeAsnwerFlag)\n"
        s += "   truncationFlag: \(self.truncationFlag)\n"
        s += "   recursionDesiredFlag: \(self.recursionDesiredFlag)\n"
        s += "   recursionAvailableFlag: \(self.recursionAvailableFlag)\n"
        s += "   responseCode: \(self.responseCode)\n"
        s += "   questionCount: \(self.questionCount)\n"
        s += "   answerRecordCount: \(self.answerRecordCount)\n"
        s += "   authorityRecordCount: \(self.authorityRecordCount)\n"
        s += "   additionalRecordCount: \(self.additionalRecordCount)\n"
        
        s += "   Queries:\n"
        for question in self.questions {
            s += question.debugDescription
        }
        return s;
    }
}
