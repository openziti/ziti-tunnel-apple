/*
Copyright NetFoundry Inc.

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
    case AppexNotification = 0
    case AppexNotificationAction
    case ErrorResponse
    case SetLogLevel
    case UpdateLogRotateConfig
    case Reassert
    case SetEnabled
    case SetEnabledResponse
    case DumpRequest
    case DumpResponse
    case MfaEnrollRequest
    case MfaEnrollResponse
    case MfaVerifyRequest
    case MfaRemoveRequest
    case MfaAuthQueryResponse
    case MfaStatusResponse
    case MfaGetRecoveryCodesRequest
    case MfaNewRecoveryCodesRequest
    case MfaRecoveryCodesResponse
    
    var type:IpcMessage.Type {
        switch self {
        case .AppexNotification: return IpcAppexNotificationMessage.self
        case .AppexNotificationAction: return IpcAppexNotificationActionMessage.self
        case .ErrorResponse: return IpcErrorResponseMessage.self
        case .SetLogLevel: return IpcSetLogLevelMessage.self
        case .UpdateLogRotateConfig: return IpcUpdateLogRotateConfigMessage.self
        case .Reassert: return IpcReassertMessage.self
        case .SetEnabled: return IpcSetEnabledMessage.self
        case .SetEnabledResponse: return IpcSetEnabledResponseMessage.self
        case .DumpRequest: return IpcDumpRequestMessage.self
        case .DumpResponse: return IpcDumpResponseMessage.self
        case .MfaEnrollRequest: return IpcMfaEnrollRequestMessage.self
        case .MfaEnrollResponse: return IpcMfaEnrollResponseMessage.self
        case .MfaVerifyRequest: return IpcMfaVerifyRequestMessage.self
        case .MfaRemoveRequest: return IpcMfaRemoveRequestMessage.self
        case .MfaAuthQueryResponse: return IpcMfaAuthQueryResponseMessage.self
        case .MfaStatusResponse: return IpcMfaStatusResponseMessage.self
        case .MfaGetRecoveryCodesRequest: return IpcMfaGetRecoveryCodesRequestMessage.self
        case .MfaNewRecoveryCodesRequest: return IpcMfaNewRecoveryCodesRequestMessage.self
        case .MfaRecoveryCodesResponse: return IpcMfaRecoveryCodesResponseMessage.self
        }
    }
}

class IpcMessage : NSObject, Codable {
    static let IpcURL:URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)?.appendingPathComponent("appex-notifications.ipc", isDirectory:false)

    class Meta : NSObject, Codable {
        enum CodingKeys: String, CodingKey { case zid, msgId, msgType }
        var zid:String?
        var msgId = UUID().uuidString
        var msgType:IpcMessageType
        var respType:IpcMessage.Type? = nil
        var createdAt = Date()
        
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

class IpcPolyMessage : NSObject, Codable {
    let msg:IpcMessage
    
    init(_ msg:IpcMessage) {
        self.msg = msg
        super.init()
    }
    required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let ipcMessage = try container.decode(IpcMessage.self)
        msg = try container.decode(ipcMessage.meta.msgType.type)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(msg)
    }
}

class IpcAppexNotificationMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case category, title, subtitle, body, actions }
    var category:String?
    var title:String?
    var subtitle:String?
    var body:String?
    var actions:[String]?
    
    init(_ zid:String?, _ category:String, _ title:String, _ subtitle:String, _ body:String, _ actions:[String]) {
        let m = Meta(zid, .AppexNotification , nil)
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.actions = actions
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try? c.decode(String.self, forKey: .category)
        title = try? c.decode(String.self, forKey: .title)
        subtitle = try? c.decode(String.self, forKey: .subtitle)
        body = try? c.decode(String.self, forKey: .body)
        actions = try? c.decode([String].self, forKey: .actions)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(actions, forKey: .actions)
    }
}

class IpcAppexNotificationActionMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case category, action }
    var category:String?
    var action:String?
    
    init(_ zid:String?, _ category:String, _ action:String) {
        let m = Meta(zid, .AppexNotificationAction , nil)
        self.category = category
        self.action = action
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try? c.decode(String.self, forKey: .category)
        action = try? c.decode(String.self, forKey: .action)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(action, forKey: .action)
    }
}

class IpcErrorResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case errorDescription, errorCode }
    var errorDescription:String?
    var errorCode:Int = -1
    
    init(_ errorDescription:String, _ errorCode:Int=Int(-1)) {
        let m = Meta(nil, .ErrorResponse)
        self.errorDescription = errorDescription
        self.errorCode = errorCode
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        errorDescription = try c.decode(String.self, forKey: .errorDescription)
        errorCode = try c.decode(Int.self, forKey: .errorCode)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(errorDescription, forKey: .errorDescription)
        try c.encodeIfPresent(errorCode, forKey: .errorCode)
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
        logLevel = try? c.decode(Int32.self, forKey: .logLevel)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(logLevel, forKey: .logLevel)
    }
}

class IpcUpdateLogRotateConfigMessage : IpcMessage {
    init() {
        let m = Meta(nil, .UpdateLogRotateConfig)
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
    }
}

class IpcReassertMessage : IpcMessage {
    init() {
        let m = Meta(nil, .Reassert)
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
    }
}

class IpcSetEnabledMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case enabled }
    var enabled:Bool?
    
    init(_ zid:String, _ enabled:Bool) {
        let m = Meta(zid, .SetEnabled, IpcSetEnabledResponseMessage.self)
        self.enabled = enabled
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try? c.decode(Bool.self, forKey: .enabled)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(enabled, forKey: .enabled)
    }
}

class IpcSetEnabledResponseMessage : IpcMessage {
    enum CodingKeys: String, CodingKey { case code }
    var code:Int64?
    
    init(_ zid:String, _ code:Int64) {
        let m = Meta(zid, .SetEnabledResponse)
        self.code = code
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try? c.decode(Int64.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
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
        dump = try? c.decode(String.self, forKey: .dump)
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
        status = try? c.decode(Int32.self, forKey: .status)
        mfaEnrollment = try? c.decode(CZiti.ZitiMfaEnrollment.self, forKey: .mfaEnrollment)
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
        code = try? c.decode(String.self, forKey: .code)
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
        let m = Meta(nil, .MfaStatusResponse)
        self.status = status
        super.init(m)
    }
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decode(Int32.self, forKey: .status)
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
        code = try? c.decode(String.self, forKey: .code)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(code, forKey: .code)
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
        code = try? c.decode(String.self, forKey: .code)
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
        code = try? c.decode(String.self, forKey: .code)
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
        code = try? c.decode(String.self, forKey: .code)
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
        status = try? c.decode(Int32.self, forKey: .status)
        codes = try? c.decode([String].self, forKey: .codes)
    }
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(codes, forKey: .codes)
    }
}
