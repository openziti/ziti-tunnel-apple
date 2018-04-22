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
    case AAAA = 28
    case PTR = 12
    case unrecognized
    
    init(_ data:UInt16) {
        switch data {
        case 1: self = .A
        case 28: self = .AAAA
        case 12: self = .PTR
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

class DNSQuestion : NSObject {
    var qName:String = ""
    var qType  = DNSRecordType.A
    var qClass = DNSRecordClass.IN
    
    static func from(_ data:Data) -> (question: DNSQuestion?, nextIndex:Int) {
        
        if data.count < 5 {
            NSLog("Invalid data for DNS Question")
            return (nil, 0)
        }
        
        let question = DNSQuestion()
        
        var count = Int(data[data.startIndex])
        var indx = data.startIndex + 1
        
        while count > 0 {
            for i in indx..<(count+indx) {
                question.qName += String(UnicodeScalar(data[i]))
            }
            indx = indx + count
            count = Int(data[indx])
            if count != 0 {
                question.qName += "."
            }
            indx = indx + 1
        }
        
        question.qType  = DNSRecordType(IPv4Utils.extractUInt16(data, from: indx))
        question.qClass = DNSRecordClass(IPv4Utils.extractUInt16(data, from: indx + 2))
        
        return (question, indx + 4)
    }
    
    override var debugDescription: String {
        return "   > " + self.qName + " type: \(self.qType), class \(self.qClass)\n"
    }
}


class DNSPacket : NSObject {
    var udp:UDPPacket
    
    init?(_ udp:UDPPacket) {
        self.udp = udp
        
        super.init()
        
        if let udpPayload = self.udp.payload {
            if udpPayload.count < 12 {
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
    
    var id:UInt16 {
        get {
            if let payload = udp.payload {
               return IPv4Utils.extractUInt16(payload, from: payload.startIndex)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data, at: payload.startIndex, value: newValue)
            }
        }
    }
    
    var qrFlag:Bool {
        get {
            if let payload = udp.payload {
                return (payload[payload.startIndex+2] >> 7) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex+2] = (prev & 0x7f) | (byteValue << 7)
            }
        }
    }
    
    var opCode:DNSOpCode {
        get {
            if let payload = udp.payload {
                return DNSOpCode(payload[payload.startIndex+2])
            }
            return .unrecognized
        }
        
        set {
            if let payload = udp.payload {
                let prev:UInt8 = udp.ip.data[payload.startIndex+2]
                udp.ip.data[payload.startIndex+2] = (prev & 0x87) | ((newValue.rawValue << 3) & 0x78)
            }
        }
    }
    
    var authoritativeAsnwerFlag:Bool {
        get {
            if let payload = udp.payload {
                return ((payload[payload.startIndex+2] >> 2) & 0x01) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex+2] = (prev & 0xfb) | (byteValue << 2)
            }
        }
    }
    
    var truncationFlag:Bool {
        get {
            if let payload = udp.payload {
                return ((payload[payload.startIndex+2] >> 1) & 0x01) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex+2] = (prev & 0xfd) | (byteValue << 1)
            }
        }
    }
    
    var recursionDesiredFlag:Bool {
        get {
            if let payload = udp.payload {
                return (payload[payload.startIndex+2] & 0x01) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex+2] = (prev & 0xfe) | byteValue
            }
        }
    }
    
    var recursionAvailableFlag:Bool {
        get {
            if let payload = udp.payload {
                return (payload[payload.startIndex+3] >> 7) != 0
            }
            return false
        }
        
        set {
            if let payload = udp.payload {
                let prev = udp.ip.data[payload.startIndex+2]
                let byteValue:UInt8 = newValue ? 0x01 : 0x00
                udp.ip.data[payload.startIndex+3] = (prev & 0x7f) | (byteValue << 7)
            }
        }
    }
    
    var responseCode:DNSResponseCode {
        get {
            if let payload = udp.payload {
                return DNSResponseCode(payload[payload.startIndex+3])
            }
            return .unrecognized
        }
        
        set {
            if let payload = udp.payload {
                let prev:UInt8 = udp.ip.data[payload.startIndex+3]
                udp.ip.data[payload.startIndex+3] = (prev & 0xf0) | (newValue.rawValue & 0x0f)
            }
        }
    }
    
    var questionCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex+4)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data, at: payload.startIndex+4, value: newValue)
            }
        }
    }
    
    var answerRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex+6)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data, at: payload.startIndex+6, value: newValue)
            }
        }
    }
    
    var authorityRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex+8)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data, at: payload.startIndex+8, value: newValue)
            }
        }
    }
    
    var additionalRecordCount:UInt16 {
        get {
            if let payload = udp.payload {
                return IPv4Utils.extractUInt16(payload, from: payload.startIndex+10)
            }
            return 0
        }
        
        set {
            if let payload = udp.payload {
                IPv4Utils.updateUInt16(&udp.ip.data, at: payload.startIndex+10, value: newValue)
            }
        }
    }
    
    var questions:[DNSQuestion] {
        var response:[DNSQuestion] = []
        
        if let payload = udp.payload {
            var qData = payload[(payload.startIndex+12)...]
            for _ in 0..<self.questionCount {
                let questionResponse = DNSQuestion.from(qData)
                
                if questionResponse.nextIndex < qData.count {
                    qData = qData[questionResponse.nextIndex...]
                }
                
                if let question = questionResponse.question {
                    response.append(question)
                }
            }
        }
        return response
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
