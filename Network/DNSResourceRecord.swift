//
//  DNSResourceRecord.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/25/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

typealias DNSQuestion = DNSResoureRecodeBase

class DNSResoureRecodeBase : NSObject {
    static let minNumBytes = 5
    let name:DNSName
    let recordType:DNSRecordType
    let recordClass:DNSRecordClass
    var numBytes = 0
    
    init?(_ data:Data, offset:Int) {
        guard data.count >= DNSQuestion.minNumBytes else { return nil }
        self.name = DNSName(data, offset:offset)
        let rTypeIndx = data.startIndex + self.name.numBytes
        self.recordType = DNSRecordType(IPUtils.extractUInt16(data, from: rTypeIndx))
        self.recordClass = DNSRecordClass(IPUtils.extractUInt16(data, from: rTypeIndx + MemoryLayout<UInt16>.size))
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
        IPUtils.appendUInt16(&data, value: self.recordType.rawValue)
        IPUtils.appendUInt16(&data, value: self.recordClass.rawValue)
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
        self.ttl = IPUtils.extractUInt32(data, from: indx)
        self.numBytes += MemoryLayout<UInt32>.size
        indx += MemoryLayout<UInt32>.size
        self.resourceDataLength = IPUtils.extractUInt16(data, from: indx)
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
        IPUtils.appendUInt32(&data, value: self.ttl)
        IPUtils.appendUInt16(&data, value: self.resourceDataLength)
        
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
            s += IPUtils.payloadToString(data)
        }
        return s
    }
}
