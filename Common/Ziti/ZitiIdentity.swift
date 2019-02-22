//
//  ZitiIdentity.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/21/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

enum ZitiPayloadError: Error {
    case exp
    case apiBaseUrl
    case enrollmentUrl
    case method
    case identity
    case identityName
    case identityId
    case token
    case versions
    case apiVersion
    case enrollmentApiVersion
    case rootCa
}

extension ZitiPayloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exp:
            return NSLocalizedString("Invalid paylod exp", comment: "Invalid exp")
        case .apiBaseUrl:
            return NSLocalizedString("Invalid payload apiBaseUrl", comment: "Invalid apiBaseUrl")
        case .enrollmentUrl:
            return NSLocalizedString("Invalid payload enrollmentUrl", comment: "Invalid enrollmentUrl")
        case .method:
            return NSLocalizedString("Invalid payload method", comment: "Invalid method")
        case .identity:
            return NSLocalizedString("Invalid payload identity", comment: "Invalid identity")
        case .identityName:
            return NSLocalizedString("Invalid payload identityName", comment: "Invalid identityName")
        case .identityId:
            return NSLocalizedString("Invalid payload identityId", comment: "Invalid identityId")
        case .token:
            return NSLocalizedString("Invalid payload token", comment: "Invalid token")
        case .versions:
            return NSLocalizedString("Invalid payload versions", comment: "Invalid versions")
        case .apiVersion:
            return NSLocalizedString("Invalid payload apiVersion", comment: "Invalid apiVersion")
        case .enrollmentApiVersion:
            return NSLocalizedString("Invalid payload enrollmentApiVersion", comment: "Invalid enrollmentApiVersion")
        case .rootCa:
            return NSLocalizedString("Invalid payload rootCa", comment: "Invalid rootCa")
        }
    }
}

class ZitiIdentity : NSObject, NSCoding {
    
    static let ZITI_IDENTITIES = "ZitiIdentities"
    
    let apiBaseUrl:String
    let enrollmentUrl:String
    let method:String
    let name:String
    let id:String
    let token:String
    let apiVersion:String
    let enrollmentApiVersion:String
    let rootCa:String
    
    var enrolled = false
    var enabled = false
    
    init(_ enrollJson:[String:Any]) throws {
       
        guard let apiBaseUrl = enrollJson["apiBaseUrl"] as? String else {
            throw ZitiPayloadError.apiBaseUrl
        }
        self.apiBaseUrl = apiBaseUrl
        
        guard let enrollmentUrl = enrollJson["enrollmentUrl"] as? String else {
            throw ZitiPayloadError.enrollmentUrl
        }
        self.enrollmentUrl = enrollmentUrl
        
        guard let method = enrollJson["method"] as? String else {
            throw ZitiPayloadError.method
        }
        self.method = method
        
        guard let token = enrollJson["token"] as? String else {
            throw ZitiPayloadError.token
        }
        self.token = token
        
        guard let rootCa = enrollJson["rootCa"] as? String else {
            throw ZitiPayloadError.rootCa
        }
        self.rootCa = rootCa
        
        // identity
        guard let identity = enrollJson["identity"] as? [String:String] else {
            throw ZitiPayloadError.identity
        }
        
        guard let identityName = identity["name"] else {
            throw ZitiPayloadError.identityName
        }
        self.name = identityName
        
        guard let id = identity["id"] else {
            throw ZitiPayloadError.identityId
        }
        self.id = id
        
        // versions
        guard let versions = enrollJson["versions"] as? [String:String] else {
            throw ZitiPayloadError.versions
        }
        
        guard let apiVersion = versions["api"] else {
            throw ZitiPayloadError.apiVersion
        }
        self.apiVersion = apiVersion
        
        guard let enrollmentApiVersion = versions["enrollmentApi"] else {
            throw ZitiPayloadError.enrollmentApiVersion
        }
        self.enrollmentApiVersion = enrollmentApiVersion
        
        super.init()
    }
    
    init(apiBaseUrl:String, enrollmentUrl:String, method:String, name:String, id:String, token:String, apiVersion:String, enrollmentApiVersion:String, rootCa:String, enrolled:Bool, enabled:Bool) {
        
        self.apiBaseUrl = apiBaseUrl
        self.enrollmentUrl = enrollmentUrl
        self.method = method
        self.name = name
        self.id = id
        self.token = token
        self.apiVersion = apiVersion
        self.enrollmentApiVersion = enrollmentApiVersion
        self.rootCa = rootCa
        self.enrolled = enrolled
        self.enabled = enabled
    }
    
    required convenience init(coder aDecoder: NSCoder) {
        let apiBaseUrl = aDecoder.decodeObject(forKey: "apiBaseUrl") as! String
        let enrollmentUrl = aDecoder.decodeObject(forKey: "enrollmentUrl") as! String
        let method = aDecoder.decodeObject(forKey: "method") as! String
        let name = aDecoder.decodeObject(forKey: "name") as! String
        let id = aDecoder.decodeObject(forKey: "id") as! String
        let token = aDecoder.decodeObject(forKey: "token") as! String
        let apiVersion = aDecoder.decodeObject(forKey: "apiVersion") as! String
        let enrollmentApiVersion = aDecoder.decodeObject(forKey: "enrollmentApiVersion") as! String
        let rootCa = aDecoder.decodeObject(forKey: "rootCa") as! String
        
        var enrolled = false
        if let e = aDecoder.decodeObject(forKey: "enrolled") {
            enrolled = e as! Bool
        }
        
        var enabled = false
        if let e = aDecoder.decodeObject(forKey: "enabled") {
            enabled = e as! Bool
        }
        
        self.init(apiBaseUrl: apiBaseUrl, enrollmentUrl: enrollmentUrl, method: method, name: name, id: id, token: token, apiVersion: apiVersion, enrollmentApiVersion: enrollmentApiVersion, rootCa: rootCa, enrolled: enrolled, enabled: enabled)
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(apiBaseUrl, forKey: "apiBaseUrl")
        aCoder.encode(enrollmentUrl, forKey: "enrollmentUrl")
        aCoder.encode(method, forKey: "method")
        aCoder.encode(name, forKey: "name")
        aCoder.encode(id, forKey: "id")
        aCoder.encode(token, forKey: "token")
        aCoder.encode(apiVersion, forKey: "apiVersion")
        aCoder.encode(enrollmentApiVersion, forKey: "enrollmentApiVersion")
        aCoder.encode(rootCa, forKey: "rootCa")
        aCoder.encode(enrolled, forKey: "enrolled")
        aCoder.encode(enabled, forKey: "enabled")
    }
    
    override var debugDescription: String {
        return "ZitiIdentity:\n" +
        "name: \(self.name)\n" +
        "id: \(self.id)\n" +
        "enrolled: \(self.enrolled)\n" +
        "enabled \(self.enabled)\n" +
        "apiBaseUrl: \(self.apiBaseUrl)\n" +
        "enrollmentUrl: \(self.enrollmentUrl)\n" +
        "method: \(self.method)\n" +
        "token: \(self.token)\n" +
        "apiVersion: \(self.apiVersion)\n" +
        "enrollmentApiVersion: \(self.enrollmentApiVersion)\n" +
        "rootCa: \(self.rootCa)\n"
    }
}
