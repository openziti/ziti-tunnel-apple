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

class ZitiIdentityTests: XCTestCase {

    // MARK: - name / id defaults

    func testName_withCzid() {
        let zid = makeIdentity(name: "My Identity")
        XCTAssertEqual(zid.name, "My Identity")
    }

    func testName_withoutCzid() {
        let zid = ZitiIdentity()
        XCTAssertEqual(zid.name, "--")
    }

    func testId_withCzid() {
        let zid = makeIdentity(id: "abc-123")
        XCTAssertEqual(zid.id, "abc-123")
    }

    func testId_withoutCzid() {
        let zid = ZitiIdentity()
        XCTAssertEqual(zid.id, "--invalid_id--")
    }

    // MARK: - networkDisplay

    func testNetworkDisplay_stripsEdgeClientV1() {
        let zid = makeIdentity(ztAPI: "https://ctrl.example.com/edge/client/v1")
        XCTAssertEqual(zid.networkDisplay, "https://ctrl.example.com")
    }

    func testNetworkDisplay_stripsEdgeClientV1WithTrailingSlash() {
        let zid = makeIdentity(ztAPI: "https://ctrl.example.com/edge/client/v1/")
        XCTAssertEqual(zid.networkDisplay, "https://ctrl.example.com")
    }

    func testNetworkDisplay_preservesCleanURL() {
        let zid = makeIdentity(ztAPI: "https://ctrl.example.com")
        XCTAssertEqual(zid.networkDisplay, "https://ctrl.example.com")
    }

    func testNetworkDisplay_emptWhenNoCzid() {
        let zid = ZitiIdentity()
        XCTAssertEqual(zid.networkDisplay, "")
    }

    // MARK: - enrollmentStatus

    func testEnrollmentStatus_enrolled() {
        let zid = makeIdentity(enrolled: true)
        XCTAssertEqual(zid.enrollmentStatus, .Enrolled)
    }

    func testEnrollmentStatus_pending_noClaims() {
        let zid = makeIdentity(enrolled: false)
        XCTAssertEqual(zid.enrollmentStatus, .Pending)
    }

    func testEnrollmentStatus_pending_futureExpiration() {
        let future = Int(Date().timeIntervalSince1970) + 86400
        let zid = makeIdentity(enrolled: false, expiration: future)
        XCTAssertEqual(zid.enrollmentStatus, .Pending)
    }

    func testEnrollmentStatus_expired() {
        let past = Int(Date().timeIntervalSince1970) - 86400
        let zid = makeIdentity(enrolled: false, expiration: past)
        XCTAssertEqual(zid.enrollmentStatus, .Expired)
    }

    func testEnrollmentStatus_enrolledTrumpsClaims() {
        // Even with expired claims, enrolled=true wins
        let past = Int(Date().timeIntervalSince1970) - 86400
        let zid = makeIdentity(enrolled: true, expiration: past)
        XCTAssertEqual(zid.enrollmentStatus, .Enrolled)
    }

    // MARK: - enrollmentStatusDisplay

    func testEnrollmentStatusDisplay_pending() {
        let zid = makeIdentity(enrolled: false)
        XCTAssertEqual(zid.enrollmentStatusDisplay, "Pending")
    }

    func testEnrollmentStatusDisplay_enrolledPlain() {
        let zid = makeIdentity(enrolled: true)
        XCTAssertEqual(zid.enrollmentStatusDisplay, "Enrolled")
    }

    func testEnrollmentStatusDisplay_enrolledCert() {
        let zid = makeIdentity(enrolled: true, enrollTo: "cert")
        XCTAssertEqual(zid.enrollmentStatusDisplay, "Enrolled (Device Certificate)")
    }

    func testEnrollmentStatusDisplay_enrolledToken() {
        let zid = makeIdentity(enrolled: true, enrollTo: "token")
        XCTAssertEqual(zid.enrollmentStatusDisplay, "Enrolled (User Session)")
    }

    func testEnrollmentStatusDisplay_enrolledExtAuth() {
        let zid = makeIdentity(
            enrolled: true,
            jwtProviders: [["name": "idp", "issuer": "https://idp.example.com",
                            "canCertEnroll": false, "canTokenEnroll": false]]
        )
        XCTAssertEqual(zid.enrollmentStatusDisplay, "Enrolled (User Session)")
    }

    func testEnrollmentStatusDisplay_enrolledExtAuthPending() {
        let zid = makeIdentity(enrolled: true, extAuthPending: true)
        XCTAssertEqual(zid.enrollmentStatusDisplay, "Enrolled (Authentication Required)")
    }

    // MARK: - needsRestart

    func testNeedsRestart_falseWhenDisabled() {
        let svc = makeServiceJSON(needsRestart: true)
        let zid = makeIdentity(enrolled: true, enabled: false, services: [svc])
        XCTAssertFalse(zid.needsRestart())
    }

    func testNeedsRestart_falseWhenNotEnrolled() {
        let svc = makeServiceJSON(needsRestart: true)
        let zid = makeIdentity(enrolled: false, enabled: true, services: [svc])
        XCTAssertFalse(zid.needsRestart())
    }

    func testNeedsRestart_trueWhenServiceNeedsRestart() {
        let svc = makeServiceJSON(needsRestart: true)
        let zid = makeIdentity(enrolled: true, enabled: true, services: [svc])
        XCTAssertTrue(zid.needsRestart())
    }

    func testNeedsRestart_falseWhenNoServicesNeedRestart() {
        let svc = makeServiceJSON(needsRestart: false)
        let zid = makeIdentity(enrolled: true, enabled: true, services: [svc])
        XCTAssertFalse(zid.needsRestart())
    }

    func testNeedsRestart_falseWhenNoServices() {
        let zid = makeIdentity(enrolled: true, enabled: true)
        XCTAssertFalse(zid.needsRestart())
    }

    // MARK: - allServicePostureChecksPassing

    func testAllPostureChecksPassing_trueWhenAllPass() {
        let svc = makeServiceJSON(postureQuerySets: [makePQS(isPassing: true)])
        let zid = makeIdentity(services: [svc])
        XCTAssertTrue(zid.allServicePostureChecksPassing())
    }

    func testAllPostureChecksPassing_falseWhenOneFails() {
        let passing = makeServiceJSON(name: "s1", id: "s1", postureQuerySets: [makePQS(isPassing: true)])
        let failing = makeServiceJSON(name: "s2", id: "s2", postureQuerySets: [makePQS(isPassing: false)])
        let zid = makeIdentity(services: [passing, failing])
        XCTAssertFalse(zid.allServicePostureChecksPassing())
    }

    func testAllPostureChecksPassing_trueWhenNoServices() {
        let zid = makeIdentity()
        XCTAssertTrue(zid.allServicePostureChecksPassing())
    }

    // MARK: - failingPostureChecks

    func testFailingPostureChecks_empty() {
        let zid = makeIdentity()
        XCTAssertEqual(zid.failingPostureChecks(), [])
    }

    func testFailingPostureChecks_collectsFromMultipleServices() {
        let svc1 = makeServiceJSON(name: "s1", id: "s1", postureQuerySets: [
            makePQS(isPassing: false, queries: [makePQ(isPassing: false, queryType: "OS")])
        ])
        let svc2 = makeServiceJSON(name: "s2", id: "s2", postureQuerySets: [
            makePQS(isPassing: false, queries: [makePQ(isPassing: false, queryType: "MAC")])
        ])
        let zid = makeIdentity(services: [svc1, svc2])
        let fails = Set(zid.failingPostureChecks())
        XCTAssertEqual(fails, Set(["OS", "MAC"]))
    }

    func testFailingPostureChecks_deduplicates() {
        let svc1 = makeServiceJSON(name: "s1", id: "s1", postureQuerySets: [
            makePQS(isPassing: false, queries: [makePQ(isPassing: false, queryType: "OS")])
        ])
        let svc2 = makeServiceJSON(name: "s2", id: "s2", postureQuerySets: [
            makePQS(isPassing: false, queries: [makePQ(isPassing: false, queryType: "OS")])
        ])
        let zid = makeIdentity(services: [svc1, svc2])
        XCTAssertEqual(zid.failingPostureChecks(), ["OS"])
    }

    // MARK: - Boolean convenience properties

    func testIsMfaEnabled() {
        XCTAssertFalse(makeIdentity().isMfaEnabled)
        XCTAssertTrue(makeIdentity(mfaEnabled: true).isMfaEnabled)
        XCTAssertFalse(makeIdentity(mfaEnabled: false).isMfaEnabled)
    }

    func testIsMfaVerified() {
        // Requires both mfaEnabled and mfaVerified
        XCTAssertFalse(makeIdentity(mfaEnabled: false, mfaVerified: true).isMfaVerified)
        XCTAssertFalse(makeIdentity(mfaEnabled: true, mfaVerified: false).isMfaVerified)
        XCTAssertTrue(makeIdentity(mfaEnabled: true, mfaVerified: true).isMfaVerified)
    }

    func testIsMfaPending() {
        XCTAssertFalse(makeIdentity().isMfaPending)
        XCTAssertTrue(makeIdentity(mfaPending: true).isMfaPending)
    }

    func testIsExtAuthEnabled() {
        XCTAssertFalse(makeIdentity().isExtAuthEnabled)
        XCTAssertTrue(makeIdentity(jwtProviders: [
            ["name": "p", "issuer": "i", "canCertEnroll": false, "canTokenEnroll": false]
        ]).isExtAuthEnabled)
        // Empty array counts as not enabled
        XCTAssertFalse(makeIdentity(jwtProviders: []).isExtAuthEnabled)
    }

    func testIsExtAuthPending() {
        XCTAssertFalse(makeIdentity().isExtAuthPending)
        XCTAssertTrue(makeIdentity(extAuthPending: true).isExtAuthPending)
    }

    // MARK: - getEnrollmentMethod

    func testGetEnrollmentMethod_ott() {
        let zid = makeIdentity(claims: ["sub": "s", "iss": "i", "em": "ott"])
        XCTAssertEqual(zid.getEnrollmentMethod(), .ott)
    }

    func testGetEnrollmentMethod_ottCa() {
        let zid = makeIdentity(claims: ["sub": "s", "iss": "i", "em": "ottCa"])
        XCTAssertEqual(zid.getEnrollmentMethod(), .ottCa)
    }

    func testGetEnrollmentMethod_url() {
        let zid = makeIdentity(claims: ["sub": "s", "iss": "i", "em": "url"])
        XCTAssertEqual(zid.getEnrollmentMethod(), .url)
    }

    func testGetEnrollmentMethod_unknown() {
        let zid = makeIdentity(claims: ["sub": "s", "iss": "i", "em": "somethingNew"])
        XCTAssertEqual(zid.getEnrollmentMethod(), .unrecognized)
    }

    func testGetEnrollmentMethod_defaultsToOtt() {
        let zid = makeIdentity()
        XCTAssertEqual(zid.getEnrollmentMethod(), .ott)
    }

    // MARK: - alreadyEnrolledInfo

    func testAlreadyEnrolledInfo_userSession() {
        let info = ZitiIdentity.alreadyEnrolledInfo(requestedType: "User Session")
        XCTAssertEqual(info.title, "User Session Enrollment Failed")
        XCTAssertEqual(info.action, "Connect as User Session")
        XCTAssertTrue(info.detail.contains("An identity already exists"))
    }

    func testAlreadyEnrolledInfo_deviceCertificate() {
        let info = ZitiIdentity.alreadyEnrolledInfo(requestedType: "Device Certificate")
        XCTAssertEqual(info.title, "Device Certificate Enrollment Failed")
        XCTAssertTrue(info.detail.contains("device certificate"))
    }

    // MARK: - appexNotifications

    func testAppexNotifications_addAndGet() {
        let zid = makeIdentity()
        let msg = IpcAppexNotificationMessage("zid-1", "cat", "title", "sub", "body", ["ok"])
        zid.addAppexNotification(msg)
        let msgs = zid.getAppexNotifications()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertTrue(msgs[0] is IpcAppexNotificationMessage)
    }

    func testAppexNotifications_emptyByDefault() {
        let zid = makeIdentity()
        // appexNotifications is nil by default, getAppexNotifications handles this
        let msgs = zid.getAppexNotifications()
        XCTAssertEqual(msgs.count, 0)
    }

    // MARK: - Enum inits

    func testEnrollmentMethodInit() {
        XCTAssertEqual(ZitiIdentity.EnrollmentMethod("ott"), .ott)
        XCTAssertEqual(ZitiIdentity.EnrollmentMethod("ottCa"), .ottCa)
        XCTAssertEqual(ZitiIdentity.EnrollmentMethod("url"), .url)
        XCTAssertEqual(ZitiIdentity.EnrollmentMethod("xyz"), .unrecognized)
    }

    func testEnrollmentStatusInit() {
        XCTAssertEqual(ZitiIdentity.EnrollmentStatus("Pending"), .Pending)
        XCTAssertEqual(ZitiIdentity.EnrollmentStatus("Expired"), .Expired)
        XCTAssertEqual(ZitiIdentity.EnrollmentStatus("Enrolled"), .Enrolled)
        XCTAssertEqual(ZitiIdentity.EnrollmentStatus("xyz"), .Unknown)
    }

    func testConnectivityStatusInit() {
        XCTAssertEqual(ZitiIdentity.ConnectivityStatus("Available"), .Available)
        XCTAssertEqual(ZitiIdentity.ConnectivityStatus("PartiallyAvailable"), .PartiallyAvailable)
        XCTAssertEqual(ZitiIdentity.ConnectivityStatus("Unavailable"), .Unavailable)
        XCTAssertEqual(ZitiIdentity.ConnectivityStatus("xyz"), .None)
    }
}
