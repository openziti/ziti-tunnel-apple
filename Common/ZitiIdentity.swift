//
//  ZitiIdentity.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/21/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

// Enrollment Method Enum
enum ZitiEnrollmentMethod : String, Codable {
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
enum ZitiEnrollmentStatus : String, Codable {
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

class ZitiIdentity : NSObject, Codable {
    //let identity:(name:String, id:String)
    class Identity : NSObject, Codable {
        let name:String, id:String
        init(_ name:String, _ id:String) {
            self.name = name; self.id = id
        }
    }
    
    //let versions:(api:String, enrollmentApi:String)
    class Versions : NSObject, Codable {
        let api:String, enrollmentApi:String
        init(_ api:String, _ enrollmentApi:String) {
            self.api = api; self.enrollmentApi = enrollmentApi
        }
    }
    
    let identity:Identity
    var name:String { return identity.name }
    var id:String { return identity.id }
    let versions:Versions
    let enrollmentUrl:String
    let apiBaseUrl:String
    let method:ZitiEnrollmentMethod
    let token:String
    let rootCa:String?
    var exp:Int = 0
    var expDate:Date { return Date(timeIntervalSince1970: TimeInterval(exp)) }
    var iat:Int = 0
    var iatDate:Date { return Date(timeIntervalSince1970: TimeInterval(iat)) }
    
    var enabled = false
    var enrolled = false
    var enrollmentStatus:ZitiEnrollmentStatus {
        if (enrolled) { return .Enrolled }
        if (Date() > expDate) { return .Expired }
        return .Pending
    }
    
    init?(_ json:[String:Any]) {
        guard let identity = json["identity"] as? [String:String],
            let name = identity["name"],
            let id = identity["id"],
            let versions = json["versions"] as? [String:String],
            let apiVersion = versions["api"],
            let enrollmentApiVersion = versions["enrollmentApi"],
            let enrollmentUrl = json["enrollmentUrl"] as? String,
            let apiBaseUrl = json["apiBaseUrl"] as? String,
            let method = json["method"] as? String,
            let token = json["token"] as? String
        else {
            NSLog("ZitiIdentity - Invalid or Unsupported Enrollment JWT")
            return nil
        }
        self.identity = Identity(name, id)
        self.versions = Versions(apiVersion, enrollmentApiVersion)
        self.enrollmentUrl = enrollmentUrl
        self.apiBaseUrl = apiBaseUrl
        self.method = ZitiEnrollmentMethod(method)
        self.token = token
        self.rootCa = json["rootCa"] as? String ?? nil
        self.exp = json["exp"] as? Int ?? 0
        self.iat = json["iat"] as? Int ?? 0
        self.enabled = json["enabled"] as? Bool ?? false
        self.enrolled = json["enabled"] as? Bool ?? false
        super.init()
    }
    
    override var debugDescription: String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        if let jsonData = try? jsonEncoder.encode(self) {
            return String(data: jsonData, encoding: .utf8)!
        }
        return("Unable to json encode \(name)")
    }
}
