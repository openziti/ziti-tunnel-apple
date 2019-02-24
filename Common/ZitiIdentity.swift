//
//  ZitiIdentity.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/21/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

// Enrollment Method Enum
enum ZitiEnrollmentMethod : String {
    case ott, ottCa, unrecognized
    init(_ str:String) {
        switch str {
        case "ott": self = .ott
        case "ottCa": self = .ottCa
        default: self = .unrecognized
        }
    }
}

// Enrollment Status Enum
enum ZitiEnrollmentStatus : String {
    case Pending, Expired, Enrolled, Unknown
    init(_ str:String) {
        switch str {
        case "Pending": self = .Pending
        case "Expired": self = .Expired
        case "Enrolled": self = .Enrolled
        default: self = .Unknown
        }
    }
}

// lose namespacing so we can share archive between app and extension
@objc(ZitiIdentity)
class ZitiIdentity : NSObject, NSCoding {
    
    // TODO: Get TEAMID programatically... (and will be diff on iOS)
    static let APP_GROUP_ID = "45L2MK8H4.ZitiPacketTunnel.group"
    static let ZITI_IDENTITY = "ZitiIdentity"
    static let ZITI_IDENTITIES = "ZitiIdentities"
    
    let exp:Int
    let iat:Int
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
    
    func enrollmentStatus() -> ZitiEnrollmentStatus {
        if (enrolled) { return .Enrolled }
        let now = Date()
        let expDate = Date(timeIntervalSince1970: TimeInterval(exp))
        if  (now > expDate) { return .Expired }
        return .Pending
    }
    
    static func loadIdentities() -> [ZitiIdentity] {
        var zitiIdentities:[ZitiIdentity] = []
        let sharedDefaults = UserDefaults(suiteName: ZitiIdentity.APP_GROUP_ID)
        if let decoded  = sharedDefaults?.object(forKey: ZitiIdentity.ZITI_IDENTITIES) {
            if let identities = NSKeyedUnarchiver.unarchiveObject(with: decoded as! Data) {
                zitiIdentities = identities as! [ZitiIdentity]
            }
        }
        return zitiIdentities
    }
    
    static func storeIdentities(_ zitiIdentities:[ZitiIdentity]) {
        let sharedDefaults = UserDefaults(suiteName: ZitiIdentity.APP_GROUP_ID)
        let encodedData: Data = NSKeyedArchiver.archivedData(withRootObject: zitiIdentities)
        sharedDefaults?.set(encodedData, forKey: ZitiIdentity.ZITI_IDENTITIES)
        sharedDefaults?.synchronize()
    }
    
    init(_ json:[String:Any]) {
        self.exp = json["exp"] as? Int ?? 0
        self.iat = json["iat"] as? Int ?? 0
        self.apiBaseUrl = json["apiBaseUrl"] as? String ?? ""
        self.enrollmentUrl = json["enrollmentUrl"] as? String ?? ""
        self.method = json["method"] as? String ?? ""
        self.token = json["token"] as? String ?? ""
        self.rootCa = json["rootCa"] as? String ?? ""
        
        // identity
        if let identity = json["identity"] as? [String:String] {
            self.name = identity["name"] ?? ""
            self.id = identity["id"] ?? ""
        } else {
            self.name = ""
            self.id = ""
        }
       
        // versions
        if let versions = json["versions"] as? [String:String]  {
            self.apiVersion = versions["api"] ?? ""
            self.enrollmentApiVersion = versions["enrollmentApi"] ?? ""
        } else {
            self.apiVersion = ""
            self.enrollmentApiVersion = ""
        }
        super.init()
    }
    
    init(exp:Int, iat:Int, apiBaseUrl:String, enrollmentUrl:String, method:String, name:String, id:String, token:String, apiVersion:String, enrollmentApiVersion:String, rootCa:String, enrolled:Bool, enabled:Bool) {
        
        self.exp = exp
        self.iat = iat
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
        let exp = aDecoder.decodeInteger(forKey: "exp")
        let iat = aDecoder.decodeInteger(forKey: "iat")
        let apiBaseUrl = aDecoder.decodeObject(forKey: "apiBaseUrl") as? String ?? ""
        let enrollmentUrl = aDecoder.decodeObject(forKey: "enrollmentUrl") as? String ?? ""
        let method = aDecoder.decodeObject(forKey: "method") as? String ?? ""
        let name = aDecoder.decodeObject(forKey: "name") as? String ?? ""
        let id = aDecoder.decodeObject(forKey: "id") as? String ?? ""
        let token = aDecoder.decodeObject(forKey: "token") as? String ?? ""
        let apiVersion = aDecoder.decodeObject(forKey: "apiVersion") as? String ?? ""
        let enrollmentApiVersion = aDecoder.decodeObject(forKey: "enrollmentApiVersion") as! String
        let rootCa = aDecoder.decodeObject(forKey: "rootCa") as! String
        let enrolled = aDecoder.decodeBool(forKey: "enrolled")
        let enabled = aDecoder.decodeBool(forKey: "enabled")
        
        self.init(exp: exp, iat: iat, apiBaseUrl: apiBaseUrl, enrollmentUrl: enrollmentUrl, method: method, name: name, id: id, token: token, apiVersion: apiVersion, enrollmentApiVersion: enrollmentApiVersion, rootCa: rootCa, enrolled: enrolled, enabled: enabled)
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(exp, forKey: "exp")
        aCoder.encode(iat, forKey: "iat")
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
            "enabled: \(self.enabled)\n" +
            "exp: \(self.exp)\n" +
            "iat: \(self.iat)\n" +
            "apiBaseUrl: \(self.apiBaseUrl)\n" +
            "enrollmentUrl: \(self.enrollmentUrl)\n" +
            "method: \(self.method)\n" +
            "token: \(self.token)\n" +
            "apiVersion: \(self.apiVersion)\n" +
            "enrollmentApiVersion: \(self.enrollmentApiVersion)\n" +
            "rootCa: \(self.rootCa)"
    }
}
