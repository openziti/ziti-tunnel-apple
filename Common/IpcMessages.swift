/*
Copyright NetFoundry, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
import Foundation
import CZiti

enum IpcMessageType : Int32, Codable {
    case Poll = 0
    case SetLogLevel
    case DumpRequest
    case DumpResponse
    case MfaEnrollRequest
    case MfaEnrollResponse
    case MfaVerifyRequest
    case MfaVerifiyResponse
    case MfaRemoveRequest
    case MfaRemoveResponse
    case MfaAuthQuery
    case MfaAuthQueryResponse
    case MfaAuthStatus
    case MfaGetRecoveryCodesRequest
    case MfaNewRecoveryCodesRequest
    case MfaRecoveryCodesResponse
}

class IpcMessage : NSObject, Codable {
    class Meta : NSObject, Codable {
        enum CodingKeys: String, CodingKey { case zid, msgId, msgType }
        var zid:String?
        var msgId = UUID().uuidString
        var msgType:IpcMessageType
        var respType:IpcMessage.Type? = nil
        
        init(_ zid:String?, _ msgType:IpcMessageType, _ respType:IpcMessage.Type?=nil) {
            self.zid = zid
            self.msgType = msgType
            self.respType = respType
        }
    }
    
    var meta:Meta
    init(_ meta:Meta) {
        self.meta = meta
    }
}

class IpcPollMessage : IpcMessage {
    init() {
        let m = Meta(nil, .Poll)
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

class IpcSetLogLevelMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case logLevel }
    var logLevel:Int32?
    
    init(_ logLevel:Int32) {
        let m = Meta(nil, .SetLogLevel)
        self.logLevel = logLevel
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logLevel = try c.decode(Int32.self, forKey: .logLevel)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(logLevel, forKey: .logLevel)
    }
}

class IpcDumpRequestMessage : IpcMessage {
    init() {
        let m = Meta(nil, .DumpRequest, IpcDumpResponseMessage.self)
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
    }
}

class IpcDumpResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case dump }
    var dump:String?
    
    init(_ dump:String) {
        let m = Meta(nil, .DumpResponse)
        self.dump = dump
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dump = try c.decode(String.self, forKey: .dump)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(dump, forKey: .dump)
    }
}

class IpcMfaEnrollRequestMessage : IpcMessage {
    init(_ zid:String) {
        let m = Meta(zid, .MfaEnrollRequest, IpcMfaEnrollResponseMessage.self)
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

class IpcMfaEnrollResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case status, mfaEnrollment }
    var status:Int32?
    var mfaEnrollment:CZiti.ZitiMfaEnrollment?
    
    init(_ status:Int32, mfaEnrollment:CZiti.ZitiMfaEnrollment?) {
        let m = Meta(nil, .MfaEnrollResponse)
        self.status = status
        self.mfaEnrollment = mfaEnrollment
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Int32.self, forKey: .status)
        mfaEnrollment = try c.decode(CZiti.ZitiMfaEnrollment.self, forKey: .mfaEnrollment)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(mfaEnrollment, forKey: .mfaEnrollment)
    }
}

class IpcMfaVerifyRequestMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case code }
    var code:String?
    
    init(_ zid:String, _ code:String) {
        let m = Meta(zid, .MfaVerifyRequest, IpcMfaStatusResponseMessage.self)
        self.code = code
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
    }
}

class IpcMfaStatusResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case status }
    var status:Int32?
    
    init(_ status:Int32) {
        let m = Meta(nil, .MfaVerifiyResponse)
        self.status = status
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Int32.self, forKey: .status)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
    }
}

class IpcMfaRemoveRequestMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case code }
    var code:String?
    
    init(_ zid:String, _ code:String) {
        let m = Meta(zid, .MfaRemoveRequest, IpcMfaStatusResponseMessage.self)
        self.code = code
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
    }
}

class IpcMfaAuthQueryMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case query }
    var query:ZitiMfaAuthQuery?
    
    init(_ zid:String, _ query:ZitiMfaAuthQuery) {
        let m = Meta(zid, .MfaAuthQuery, nil) //IpcMfaAuthQueryResponseMessage.self)
        self.query = query
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(ZitiMfaAuthQuery.self, forKey: .query)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(query, forKey: .query)
    }
}

class IpcMfaAuthQueryResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case code }
    var code:String?
    
    init(_ zid:String, _ code:String) {
        let m = Meta(zid, .MfaAuthQueryResponse, IpcMfaStatusResponseMessage.self)
        self.code = code
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
    }
}

class IpcMfaGetRecoveryCodesRequestMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case code }
    var code:String?
    
    init(_ zid:String, _ code:String) {
        let m = Meta(zid, .MfaGetRecoveryCodesRequest, IpcMfaRecoveryCodesResponseMessage.self)
        self.code = code
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
    }
}

class IpcMfaNewRecoveryCodesRequestMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case code }
    var code:String?
    
    init(_ zid:String, _ code:String) {
        let m = Meta(zid, .MfaNewRecoveryCodesRequest, IpcMfaRecoveryCodesResponseMessage.self)
        self.code = code
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
    }
}

class IpcMfaRecoveryCodesResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case status, codes }
    var status:Int32?
    var codes:[String]?
    
    init(_ status:Int32, _ codes:[String]?) {
        let m = Meta(nil, .MfaRecoveryCodesResponse)
        self.status = status
        self.codes = codes
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Int32.self, forKey: .status)
        codes = try c.decode([String].self, forKey: .codes)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(codes, forKey: .codes)
    }
}
