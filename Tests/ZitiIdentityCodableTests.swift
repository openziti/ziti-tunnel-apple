//
// Copyright NetFoundry Inc.
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

import XCTest
@testable import Ziti_Desktop_Edge

class ZitiIdentityCodableTests: XCTestCase {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // MARK: - Basic round-trip

    func testRoundTrip_minimalIdentity() throws {
        let original = makeIdentity(id: "id-1", name: "Test")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertEqual(decoded.id, "id-1")
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.enrolled, false)
        XCTAssertEqual(decoded.enabled, false)
    }

    func testRoundTrip_enrolledIdentity() throws {
        let original = makeIdentity(
            id: "id-enrolled",
            ztAPI: "https://ctrl.example.com",
            name: "Enrolled Identity",
            enrolled: true,
            enabled: true,
            enrollTo: "cert"
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertEqual(decoded.id, "id-enrolled")
        XCTAssertEqual(decoded.name, "Enrolled Identity")
        XCTAssertEqual(decoded.networkDisplay, "https://ctrl.example.com")
        XCTAssertEqual(decoded.isEnrolled, true)
        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.effectiveEnrollTo, .cert)
        XCTAssertEqual(decoded.enrollmentStatus, .Enrolled)
        XCTAssertEqual(decoded.enrollmentStatusDisplay, "Enrolled (Device Certificate)")
    }

    // MARK: - Claims survive round-trip

    func testRoundTrip_withClaims() throws {
        let futureExp = Int(Date().timeIntervalSince1970) + 86400
        let original = makeIdentity(
            id: "id-claims",
            expiration: futureExp
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertNotNil(decoded.claims)
        XCTAssertEqual(decoded.claims?.sub, "id-claims")
        XCTAssertEqual(decoded.claims?.exp, futureExp)
        XCTAssertEqual(decoded.enrollmentStatus, .Pending)
    }

    func testRoundTrip_expiredClaims() throws {
        let pastExp = Int(Date().timeIntervalSince1970) - 86400
        let original = makeIdentity(expiration: pastExp)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertEqual(decoded.enrollmentStatus, .Expired)
    }

    func testRoundTrip_claimsWithEnrollmentMethod() throws {
        let original = makeIdentity(
            claims: ["sub": "test", "iss": "https://ctrl", "em": "ottCa"]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertEqual(decoded.getEnrollmentMethod(), .ottCa)
    }

    // MARK: - MFA flags survive round-trip

    func testRoundTrip_mfaFlags() throws {
        let original = makeIdentity(mfaEnabled: true, mfaVerified: true, mfaPending: false)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertTrue(decoded.isMfaEnabled)
        XCTAssertTrue(decoded.isMfaVerified)
        XCTAssertFalse(decoded.isMfaPending)
    }

    // MARK: - External auth round-trip

    func testRoundTrip_extAuthPending() throws {
        let original = makeIdentity(enrolled: true, extAuthPending: true)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertTrue(decoded.isExtAuthPending)
        XCTAssertEqual(decoded.enrollmentStatusDisplay, "Enrolled (Authentication Required)")
    }

    func testRoundTrip_jwtProviders() throws {
        let original = makeIdentity(
            enrolled: true,
            jwtProviders: [
                ["name": "Google", "issuer": "https://accounts.google.com",
                 "canCertEnroll": true, "canTokenEnroll": false]
            ]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertTrue(decoded.isExtAuthEnabled)
        XCTAssertEqual(decoded.jwtProviders?.count, 1)
        XCTAssertEqual(decoded.enrollmentStatusDisplay, "Enrolled (User Session)")
    }

    // MARK: - Services survive round-trip

    func testRoundTrip_withServices() throws {
        let svcJSON = makeServiceJSON(name: "my-service", id: "svc-1", needsRestart: true)
        let original = makeIdentity(enrolled: true, enabled: true, services: [svcJSON])
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertEqual(decoded.services.count, 1)
        XCTAssertEqual(decoded.services[0].name, "my-service")
        XCTAssertEqual(decoded.services[0].id, "svc-1")
        XCTAssertTrue(decoded.needsRestart())
    }

    func testRoundTrip_servicePostureChecks() throws {
        let svcJSON = makeServiceJSON(
            name: "posture-svc", id: "svc-p",
            postureQuerySets: [
                makePQS(isPassing: false, queries: [
                    makePQ(isPassing: false, queryType: "OS"),
                    makePQ(isPassing: true, queryType: "MAC")
                ])
            ]
        )
        let original = makeIdentity(services: [svcJSON])
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertFalse(decoded.allServicePostureChecksPassing())
        XCTAssertEqual(decoded.failingPostureChecks(), ["OS"])
    }

    // MARK: - Edge status round-trip

    func testRoundTrip_edgeStatus() throws {
        let original = makeIdentity()
        original.edgeStatus = ZitiIdentity.EdgeStatus(
            Date().timeIntervalSince1970, status: .Available
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        XCTAssertNotNil(decoded.edgeStatus)
        XCTAssertEqual(decoded.edgeStatus?.status, .Available)
    }

    // MARK: - EnrollTo round-trip

    func testRoundTrip_enrollToNone() throws {
        let original = makeIdentity(enrolled: true, enrollTo: "none")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)
        XCTAssertEqual(decoded.effectiveEnrollTo, .none)
    }

    func testRoundTrip_enrollToCert() throws {
        let original = makeIdentity(enrolled: true, enrollTo: "cert")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)
        XCTAssertEqual(decoded.effectiveEnrollTo, .cert)
    }

    func testRoundTrip_enrollToToken() throws {
        let original = makeIdentity(enrolled: true, enrollTo: "token")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)
        XCTAssertEqual(decoded.effectiveEnrollTo, .token)
    }

    // MARK: - Appex notifications round-trip

    func testRoundTrip_appexNotifications() throws {
        let original = makeIdentity()
        let notification = IpcAppexNotificationMessage(
            "zid-1", "mfa", "MFA Required", "Identity X", "Please verify", ["OK"]
        )
        original.addAppexNotification(notification)

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        let msgs = decoded.getAppexNotifications()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertTrue(msgs[0] is IpcAppexNotificationMessage)
        let decodedNotification = msgs[0] as! IpcAppexNotificationMessage
        XCTAssertEqual(decodedNotification.title, "MFA Required")
        XCTAssertEqual(decodedNotification.actions, ["OK"])
    }

    // MARK: - Fully populated identity

    func testRoundTrip_fullyPopulated() throws {
        let svcJSON = makeServiceJSON(
            name: "full-svc", id: "svc-full",
            needsRestart: false,
            postureQuerySets: [makePQS(isPassing: true)]
        )
        let original = makeIdentity(
            id: "full-id",
            ztAPI: "https://ctrl.full.example.com",
            name: "Full Identity",
            enrolled: true,
            enabled: true,
            enrollTo: "token",
            mfaEnabled: true,
            mfaVerified: true,
            mfaPending: false,
            extAuthPending: false,
            expiration: Int(Date().timeIntervalSince1970) + 86400,
            jwtProviders: [
                ["name": "Google", "issuer": "https://accounts.google.com",
                 "canCertEnroll": false, "canTokenEnroll": true]
            ],
            services: [svcJSON]
        )
        original.controllerVersion = "v0.34.2"
        original.edgeStatus = ZitiIdentity.EdgeStatus(
            Date().timeIntervalSince1970, status: .Available
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ZitiIdentity.self, from: data)

        // Core identity
        XCTAssertEqual(decoded.id, "full-id")
        XCTAssertEqual(decoded.name, "Full Identity")
        XCTAssertEqual(decoded.networkDisplay, "https://ctrl.full.example.com")
        XCTAssertEqual(decoded.controllerVersion, "v0.34.2")

        // Enrollment
        XCTAssertEqual(decoded.enrollmentStatus, .Enrolled)
        XCTAssertEqual(decoded.enrollmentStatusDisplay, "Enrolled (User Session)")
        XCTAssertEqual(decoded.effectiveEnrollTo, .token)
        XCTAssertTrue(decoded.isEnrolled)
        XCTAssertTrue(decoded.isEnabled)

        // MFA
        XCTAssertTrue(decoded.isMfaEnabled)
        XCTAssertTrue(decoded.isMfaVerified)
        XCTAssertFalse(decoded.isMfaPending)

        // External auth
        XCTAssertTrue(decoded.isExtAuthEnabled)
        XCTAssertFalse(decoded.isExtAuthPending)
        XCTAssertEqual(decoded.jwtProviders?.count, 1)

        // Edge status
        XCTAssertEqual(decoded.edgeStatus?.status, .Available)

        // Services
        XCTAssertEqual(decoded.services.count, 1)
        XCTAssertEqual(decoded.services[0].name, "full-svc")
        XCTAssertTrue(decoded.allServicePostureChecksPassing())
        XCTAssertFalse(decoded.needsRestart())
    }
}
