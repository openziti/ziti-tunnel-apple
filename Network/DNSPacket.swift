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
    
    init(_ refPacket:DNSPacket, questions:[DNSQuestion]?, answers:[DNSResourceRecord]?) {
        self.udp = UDPPacket(refPacket.udp, payload:Data(count:12))
        
        super.init()
        
        self.id = refPacket.id
        self.qrFlag = true
        self.opCode = DNSOpCode.query
        self.recursionDesiredFlag = refPacket.recursionDesiredFlag
        self.authoritativeAsnwerFlag = true
        self.responseCode = DNSResponseCode.noError
        self.questions = (questions != nil) ? questions! : []
        self.answerRecords = (answers != nil) ? answers! : []
    }
    
    var id:UInt16 {
        get {
            if let payload = udp.payload {
               return IPUtils.extractUInt16(payload,
                                              from: payload.startIndex + DNSPacket.idOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPUtils.updateUInt16(&udp.ip.data,
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
                let prev = udp.ip.data[payload.startIndex + DNSPacket.flagsOffset]
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
                let prev = udp.ip.data[payload.startIndex + DNSPacket.flagsOffset]
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
                return IPUtils.extractUInt16(payload, from: payload.startIndex + DNSPacket.questionCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPUtils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex+DNSPacket.questionCountOffset,
                                       value: newValue)
            }
        }
    }
    
    var answerRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPUtils.extractUInt16(payload, from: payload.startIndex + DNSPacket.answerRecordCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPUtils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.answerRecordCountOffset,
                                       value: newValue)
            }
        }
    }
    
    var authorityRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPUtils.extractUInt16(payload, from: payload.startIndex + DNSPacket.authorityRecordCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPUtils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.authorityRecordCountOffset,
                                       value: newValue)
            }
        }
    }
    
    var additionalRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPUtils.extractUInt16(payload, from: payload.startIndex + DNSPacket.additionalRecordCountOffset)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPUtils.updateUInt16(&udp.ip.data,
                                       at: payload.startIndex + DNSPacket.additionalRecordCountOffset,
                                       value: newValue)
            }
        }
    }
    
    private func getResourceRecords(recordStartIndx:Int, recordCount:Int) -> [DNSResourceRecord] {
        var response:[DNSResourceRecord] = []
        
        if let payload = udp.payload {
            var dnsData = payload[(payload.startIndex + DNSPacket.answersOffset + recordStartIndx)...]
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
            
            let startIndx = payload.startIndex + DNSPacket.answersOffset + recordStartIndx
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
    
    func updateLengthsAndChecksums() {
        self.udp.updateLengthsAndChecksums()
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
        
        s += "\n   Queries:\n"
        for question in self.questions {
            s += question.debugDescription
        }
        
        s += "\n   Answers:\n"
        for answer in self.answerRecords {
            s += answer.debugDescription
        }
        
        s += "\n   Authority:\n"
        for authority in self.authorityRecords {
            s += authority.debugDescription
        }
        
        s += "\n   Additional:\n"
        for additional in self.additionalRecords {
            s += additional.debugDescription
        }
        
        return s;
    }
}
