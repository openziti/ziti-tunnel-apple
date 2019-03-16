//
//  ZitiIdentity.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/21/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiIdentity : NSObject, Codable {
    //let identity:(name:String, id:String)
    class Identity : Codable {
        let name:String, id:String
        init(_ name:String, _ id:String) {
            self.name = name; self.id = id
        }
    }
    
    //let versions:(api:String, enrollmentApi:String)
    class Versions : Codable {
        let api:String, enrollmentApi:String
        init(_ api:String, _ enrollmentApi:String) {
            self.api = api; self.enrollmentApi = enrollmentApi
        }
    }
    
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
    
    let identity:Identity
    var name:String { return identity.name }
    var id:String { return identity.id }
    var sessionToken:String?
    let versions:Versions
    let enrollmentUrl:String
    let apiBaseUrl:String
    let method:EnrollmentMethod
    let token:String
    let rootCa:String?
    var exp:Int = 0
    var expDate:Date { return Date(timeIntervalSince1970: TimeInterval(exp)) }
    var iat:Int? = 0
    var iatDate:Date { return Date(timeIntervalSince1970: TimeInterval(iat ?? 0)) }
    
    var enabled:Bool? = false
    var enrolled:Bool? = false
    var enrollmentStatus:EnrollmentStatus {
        let enrolled = self.enrolled ?? false
        if (enrolled) { return .Enrolled }
        if (Date() > expDate) { return .Expired }
        return .Pending
    }
    var isEnabled:Bool { return enabled ?? false }
    var isEnrolled:Bool { return enrolled ?? false }
    var edgeStatus:EdgeStatus?
    var services:[ZitiEdgeService]?
    
    func doServicesMatch(_ other:[ZitiEdgeService]?) -> Bool {
        let curr = self.services
        if curr == nil && other == nil { return true }
        if curr == nil || other == nil { return false }
        if curr!.count != other!.count { return false }
        for i in 0..<curr!.count {
            let svc = curr![i]
            let match = other!.first(where: { $0.id == svc.id })
            if match == nil { return false }
            if (match!.name != svc.name) { return false }
            if (match!.dns?.hostname != svc.dns?.hostname) { return false }
            if (match!.dns?.port != svc.dns?.port) { return false }
        }
        return true
    }
    
    private class Cache : Codable {
        var secId:SecIdentity?
        var edge:ZitiEdge?
        init() {}
        required init(from decoder: Decoder) throws { }
        func encode(to encoder: Encoder) throws { }
    }
    private let cache = Cache()
    var secId:SecIdentity? {
        print("getting secId for \(name)")
        if cache.secId == nil {
            print("...from cache")
            (cache.secId, _) = ZitiKeychain().getSecureIdentity(self)
        }
        return cache.secId
    }
    
    lazy var edge:ZitiEdge = {
        if cache.edge == nil {
            cache.edge = ZitiEdge(self)
        }
        return cache.edge!
    }()
    
    override var debugDescription: String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        if let jsonData = try? jsonEncoder.encode(self) {
            return String(data: jsonData, encoding: .utf8)!
        }
        return("Unable to json encode \(name)")
    }
    
    deinit {
        cache.edge?.finishTasksAndInvalidate()
    }
}
