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
    var iat:Int? = 0
    var iatDate:Date { return Date(timeIntervalSince1970: TimeInterval(iat ?? 0)) }
    
    var enabled:Bool? = false
    var enrolled:Bool? = false
    var enrollmentStatus:ZitiEnrollmentStatus {
        let enrolled = self.enrolled ?? false
        if (enrolled) { return .Enrolled }
        if (Date() > expDate) { return .Expired }
        return .Pending
    }
    var isEnabled:Bool {
        return enabled ?? false
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
