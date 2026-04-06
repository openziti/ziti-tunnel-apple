//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import CZiti

class ZitiIdentity : NSObject, Codable {
    
    enum EnrollTo : String, Codable {
        case none, cert, token
    }

    enum EnrollmentMethod : String, Codable {
        case ott, ottCa, url, unrecognized
        init(_ str:String) {
            switch str {
            case "ott": self = .ott
            case "ottCa": self = .ottCa
            case "url": self = .url
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
    var enrollTo:EnrollTo?
    var jwtProviders:[CZiti.JWTProvider]?
    var selectedJWTProvider:CZiti.JWTProvider?
    var extAuthPending:Bool? = false
    
    var name:String { return czid?.name ?? "--" }
    var id:String { return czid?.id ?? "--invalid_id--" }
    
    // returned from /version, retrieved when validating JWT, polled periodically
    var controllerVersion:String?

    var expDate:Date? {
        if let exp = claims?.exp {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }
    
    var mfaEnabled:Bool? = false
    var mfaVerified:Bool? = false
    var lastMfaAuth:Date?
    var mfaPending:Bool? = false
    var enabled:Bool? = false
    var enrolled:Bool? = false
    var enrollmentStatus:EnrollmentStatus {
        let enrolled = self.enrolled ?? false
        if (enrolled) { return .Enrolled }
        if let expDate = expDate {
            if (Date() > expDate) { return .Expired }
        }
        return .Pending
    }
    
    var appexNotifications:[IpcPolyMessage]?
    func getAppexNotifications() -> [IpcMessage] {
        var msgs:[IpcMessage] = []
        appexNotifications?.forEach {
            msgs.append($0.msg)
        }
        return msgs
    }
    
    func addAppexNotification(_ msg:IpcMessage) {
        if appexNotifications == nil {
            appexNotifications = []
        }
        appexNotifications?.append(IpcPolyMessage(msg))
    }
    
    func getEnrollmentMethod() -> EnrollmentMethod {
        if let m = claims?.em { return EnrollmentMethod(m) }
        return EnrollmentMethod.ott
    }
    
    var isMfaEnabled:Bool { return mfaEnabled ?? false }
    var isMfaVerified:Bool { return isMfaEnabled && (mfaVerified ?? false) }
    var isMfaPending:Bool { return mfaPending ?? false }
    var effectiveEnrollTo:EnrollTo { return enrollTo ?? .none }
    var isExtAuthEnabled:Bool { return jwtProviders != nil && !jwtProviders!.isEmpty }
    var isExtAuthPending:Bool { return extAuthPending ?? false }
    var isEnabled:Bool { return enabled ?? false }
    var isEnrolled:Bool { return enrolled ?? false }
    var edgeStatus:EdgeStatus?
    var services:[ZitiService] = []
    
    func needsRestart() -> Bool {
        var needsRestart = false
        if isEnabled && isEnrolled {
            let restarts = services.filter {
                if let status = $0.status, let needsRestart = status.needsRestart {
                    return needsRestart
                }
                return false
            }
            needsRestart = restarts.count > 0
        }
        return needsRestart
    }
    
    func allServicePostureChecksPassing() -> Bool {
        for svc in services {
            if !svc.postureChecksPassing() {
                return false
            }
        }
        return true
    }
    
    func failingPostureChecks() -> [String] {
        var fails:[String] = []
        services.forEach { svc in
            fails += svc.failingPostureChecks()
        }
        return Array(Set(fails))
    }
    
    override var debugDescription: String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        if let jsonData = try? jsonEncoder.encode(self), let str = String(data: jsonData, encoding: .utf8) {
            return str
        }
        return("Unable to json encode \(name)")
    }

    // MARK: - Enrollment Support

    /// Apply enrollment response to this identity. Returns whether the identity ID changed.
    func applyEnrollmentResponse(_ zidResp: CZiti.ZitiIdentity, enrollTo: EnrollTo,
                                 zidStore: ZitiIdentityStore) -> Bool {
        let tempId = self.id
        let realId = zidResp.id
        let originalName = self.name

        // Validate ztAPIs - SDK sometimes returns controller IDs instead of URLs
        let validZtAPIs: [String]
        if let apis = zidResp.ztAPIs, apis.allSatisfy({ $0.contains("://") }) {
            validZtAPIs = apis
        } else {
            validZtAPIs = [zidResp.ztAPI]
        }

        let idChanged = realId != tempId
        if idChanged {
            _ = zidStore.remove(self)
            self.czid = CZiti.ZitiIdentity(id: realId, ztAPIs: validZtAPIs)
        }
        if self.czid == nil {
            self.czid = CZiti.ZitiIdentity(id: realId, ztAPIs: validZtAPIs)
        }

        self.czid?.ca = zidResp.ca
        self.czid?.certs = zidResp.certs
        self.czid?.ztAPI = zidResp.ztAPI
        self.czid?.ztAPIs = validZtAPIs
        self.czid?.name = zidResp.name ?? originalName

        self.enrollTo = enrollTo
        self.enabled = true
        self.enrolled = true

        if idChanged {
            _ = zidStore.store(self)
        }
        return idChanged
    }

    /// Text for the "already enrolled" fallback dialog.
    static func alreadyEnrolledInfo(requestedType: String) -> (title: String, detail: String, action: String) {
        let title = "\(requestedType) Enrollment Failed"
        let action = "Connect as User Session"
        let detail: String
        if requestedType == "User Session" {
            detail = "An identity already exists on this network for your account.\n\n" +
                "You can connect using the existing identity with periodic login required."
        } else {
            detail = "An identity already exists on this network for your account.\n\n" +
                "You can connect using the existing identity, but it will use session-based " +
                "authentication (periodic login required) instead of \(requestedType.lowercased())."
        }
        return (title, detail, action)
    }

    /// Enrollment status display string including type suffix.
    var enrollmentStatusDisplay: String {
        var str = enrollmentStatus.rawValue
        if isEnrolled {
            switch effectiveEnrollTo {
            case .cert: str += " (Device Certificate)"
            case .token: str += " (User Session)"
            case .none:
                if isExtAuthEnabled || isExtAuthPending {
                    str += isExtAuthPending ? " (Authentication Required)" : " (User Session)"
                }
            }
        }
        return str
    }
}

// MARK: - Enrollment Error Detection

extension CZiti.ZitiError {
    var isAlreadyEnrolled: Bool {
        if let code = errorCodeString {
            return code == "ENROLLMENT_IDENTITY_ALREADY_ENROLLED"
        }
        let desc = localizedDescription
        return desc.contains("ENROLLMENT_IDENTITY_ALREADY_ENROLLED") ||
               desc.contains("already has a matching identity")
    }
}
