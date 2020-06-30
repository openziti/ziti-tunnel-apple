//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import CZiti

class ZitiIdentity : NSObject, Codable {
    
    enum EnrollmentMethod : String, Codable {
        case ott, ottCa, unrecognized
        init(_ str:String) {
            switch str {
            case "ott": self = .ott
            case "ottCa": self = .ottCa
            default: self = .unrecognized
            }
        }
    }
    
    enum EnrollmentStatus : String, Codable {
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
    
    //None, Available, PartiallyAvailable, Unavailable
    enum ConnectivityStatus : String, Codable {
        case None, Available, PartiallyAvailable, Unavailable
        init(_ str:String) {
            switch str {
            case "Available": self = .Available
            case "PartiallyAvailable": self = .PartiallyAvailable
            case "Unavailable": self = .Unavailable
            default: self = .None
            }
        }
    }
    
    class EdgeStatus : Codable {
        let lastContactAt:TimeInterval
        let status:ConnectivityStatus
        init(_ lastContactAt:TimeInterval, status:ConnectivityStatus) {
            self.lastContactAt = lastContactAt
            self.status = status
        }
    }
    
    var czid:CZiti.ZitiIdentity?
    var claims:CZiti.ZitiClaims?
    
    var name:String { return czid?.name ?? "--" }
    var id:String { return czid?.id ?? "--invalid_id--" }
    
    // returned from /version, retrieved when validating JWT, polled periodically
    var controllerVersion:String?

    var expDate:Date { return Date(timeIntervalSince1970: TimeInterval(claims?.exp ?? 0)) }
    
    var enabled:Bool? = false
    var enrolled:Bool? = false
    var enrollmentStatus:EnrollmentStatus {
        let enrolled = self.enrolled ?? false
        if (enrolled) { return .Enrolled }
        if (Date() > expDate) { return .Expired }
        return .Pending
    }
    
    func getEnrollmentMethod() -> EnrollmentMethod {
        if let m = claims?.em { return EnrollmentMethod(m) }
        return EnrollmentMethod.ott
    }
    
    var isEnabled:Bool { return enabled ?? false }
    var isEnrolled:Bool { return enrolled ?? false }
    var edgeStatus:EdgeStatus?
    var services:[ZitiService] = []
    
    override var debugDescription: String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        if let jsonData = try? jsonEncoder.encode(self) {
            return String(data: jsonData, encoding: .utf8)!
        }
        return("Unable to json encode \(name)")
    }    
}
