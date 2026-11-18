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
import CZiti
@testable import Ziti_Desktop_Edge

private typealias ZitiIdentity = Ziti_Desktop_Edge.ZitiIdentity

final class EnrollmentLinkTests: XCTestCase {

    private func link(_ str:String) -> EnrollmentLink? {
        return EnrollmentLink(URL(string: str)!)
    }

    func testControllerLink() {
        let l = link("ziti://enroll?controller=https%3A%2F%2Fctrl.example.com%3A1280")
        let url = URL(string: "https://ctrl.example.com:1280")!
        XCTAssertEqual(l?.source, .controller(url))
        XCTAssertEqual(l?.controller, url)
        XCTAssertEqual(l?.controllerName, "ctrl.example.com:1280")
        XCTAssertEqual(l?.hint, Enrollment.Hint())
    }

    func testControllerLinkUnencoded() {
        XCTAssertEqual(link("ziti://enroll?controller=https://ctrl.example.com")?.controllerName, "ctrl.example.com")
    }

    func testSchemeAndHostCaseInsensitive() {
        XCTAssertNotNil(link("Ziti://Enroll?controller=https://ctrl.example.com"))
    }

    func testNetworkJwtLink() {
        let token = makeNetworkJwt()
        let l = link("ziti://enroll?jwt=\(token)")
        XCTAssertEqual(l?.source, .jwt(token))
        XCTAssertEqual(l?.controllerName, "ctrl.example.com:443")
    }

    func testRejectsOneTimeTokens() {
        XCTAssertNil(link("ziti://enroll?jwt=\(makeJwt(["iss": "https://ctrl.example.com", "sub": "abc", "em": "ott"]))"))
        XCTAssertNil(link("ziti://enroll?jwt=\(makeJwt(["iss": "https://ctrl.example.com", "sub": "abc", "em": "ottca"]))"))
        XCTAssertNil(link("ziti://enroll?jwt=\(makeJwt(["iss": "https://ctrl.example.com", "sub": "abc"]))"))
    }

    func testHints() {
        let l = link("ziti://enroll?controller=https://ctrl.example.com&provider=alpha&type=cert")
        XCTAssertEqual(l?.hint, Enrollment.Hint(provider: "alpha", enrollTo: .cert))
        XCTAssertEqual(link("ziti://enroll?jwt=\(makeNetworkJwt())&type=token")?.hint, Enrollment.Hint(provider: nil, enrollTo: .token))
    }

    func testRejectsUnknownType() {
        XCTAssertNil(link("ziti://enroll?controller=https://ctrl.example.com&type=none"))
        XCTAssertNil(link("ziti://enroll?controller=https://ctrl.example.com&type=Cert"))
    }

    func testRejectsOtherLinks() {
        XCTAssertNil(link("https://ctrl.example.com"))
        XCTAssertNil(link("openziti://enroll?controller=https://ctrl.example.com"))
        XCTAssertNil(link("ziti://other?controller=https://ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll"))
        XCTAssertNil(link("ziti://enroll?provider=alpha"))
    }

    func testRejectsBothKinds() {
        XCTAssertNil(link("ziti://enroll?controller=https://ctrl.example.com&jwt=\(makeNetworkJwt())"))
    }

    func testRejectsNonHttpsController() {
        XCTAssertNil(link("ziti://enroll?controller=http://ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?controller=ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?controller=https://user@ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?controller=https://:pw@ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?controller="))
        XCTAssertNil(link("ziti://enroll?jwt=\(makeNetworkJwt("http://ctrl.example.com"))"))
    }

    func testRejectsEncodedHosts() {
        XCTAssertNil(link("ziti://enroll?controller=https%3A%2F%2F..%252F..%252Fx"))
        XCTAssertNil(link("ziti://enroll?controller=https%3A%2F%2Fctrl.example.com%250Aevil"))
        XCTAssertNil(link("ziti://enroll?jwt=\(makeNetworkJwt("https://..%2F..%2Fx/"))"))
    }

    func testRejectsControllerQueryOrFragment() {
        XCTAssertNil(link("ziti://enroll?controller=https%3A%2F%2Fctrl.example.com%3Fx%3D1"))
        XCTAssertNil(link("ziti://enroll?controller=https%3A%2F%2Fctrl.example.com%23x"))
    }

    func testFirstOfRepeatedParameterWins() {
        XCTAssertEqual(link("ziti://enroll?controller=https://a.example.com&controller=https://b.example.com")?.controllerName, "a.example.com")
    }

    func testIPv6Controller() {
        XCTAssertEqual(link("ziti://enroll?controller=https%3A%2F%2F%5B%3A%3A1%5D%3A1280")?.controllerName, "::1:1280")
    }

    func testRejectsMalformedJwt() {
        XCTAssertNil(link("ziti://enroll?jwt=not-a-jwt"))
        XCTAssertNil(link("ziti://enroll?jwt=a.b.c"))
        XCTAssertNil(link("ziti://enroll?jwt=\(makeJwt(["em": "network"]))"))
    }

    func testRedacted() {
        XCTAssertEqual(EnrollmentLink.redacted(URL(string: "ziti://enroll?jwt=\(makeNetworkJwt())#x")!), "ziti://enroll")
        XCTAssertEqual(EnrollmentLink.redacted(URL(string: "https://ctrl.example.com:1280/path")!), "https://ctrl.example.com:1280/path")
        XCTAssertEqual(EnrollmentLink.redacted(URL(string: "https://user:pw@ctrl.example.com")!), "https://ctrl.example.com")
    }

    // MARK: - Pending identities

    /// An identity added by URL, or from a JWT with the given enrollment method
    private func identity(_ ztAPI:String, em:String? = nil, enrolled:Bool = false) -> ZitiIdentity {
        let zid = ZitiIdentity()
        zid.czid = CZiti.ZitiIdentity(id: UUID().uuidString, ztAPIs: [ztAPI])
        if let em = em {
            let json = try! JSONSerialization.data(withJSONObject: ["sub": "abc", "iss": ztAPI, "em": em])
            zid.claims = try! JSONDecoder().decode(CZiti.ZitiClaims.self, from: json)
        }
        zid.enrolled = enrolled
        return zid
    }

    private func url(_ str:String) -> URL { URL(string: str)! }

    func testPendingMatchesController() {
        let zid = identity("https://ctrl.example.com:1280")
        let zids = [identity("https://other.example.com:1280"), zid]
        XCTAssertTrue(zids.pending(controller: url("https://ctrl.example.com:1280/"), networkJwt: false) === zid)
    }

    func testPendingMatchesNetworkJwtIssuer() {
        let zid = identity("https://ctrl.example.com:443/", em: "network")
        XCTAssertTrue([identity("https://ctrl.example.com:443/"), zid].pending(controller: url("https://ctrl.example.com:443/"), networkJwt: true) === zid)
    }

    func testPendingMatchesSameControllerWrittenDifferently() {
        let zid = identity("https://CTRL.example.com")
        XCTAssertTrue([zid].pending(controller: url("https://ctrl.example.com:443"), networkJwt: false) === zid)
    }

    func testPendingIgnoresEnrolledAndOtherPorts() {
        let zids = [identity("https://ctrl.example.com:1280", enrolled: true), identity("https://ctrl.example.com:443")]
        XCTAssertNil(zids.pending(controller: url("https://ctrl.example.com:1280"), networkJwt: false))
    }

    func testPendingIgnoresOtherSources() {
        let zids = [identity("https://ctrl.example.com:443", em: "ott"), identity("https://ctrl.example.com:443", em: "network")]
        XCTAssertNil(zids.pending(controller: url("https://ctrl.example.com:443"), networkJwt: false))
        XCTAssertNil([identity("https://ctrl.example.com:443", em: "ott")].pending(controller: url("https://ctrl.example.com:443"), networkJwt: true))
    }

    private func withStore(_ test:(TestableZitiIdentityStore) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("EnrollmentLinkTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(TestableZitiIdentityStore(testDir: dir))
    }

    private func jwtFile(_ jwt:String, in dir:URL) -> URL {
        let file = dir.appendingPathComponent("\(UUID().uuidString).jwt")
        try! jwt.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func testInsertFromURLRefusesAnotherPendingForTheController() throws {
        try withStore { store in
            var zids:[ZitiIdentity] = []
            XCTAssertNoThrow(try zids.insertFromURL(url("https://ctrl.example.com:1280"), store, at: 0))
            XCTAssertThrowsError(try zids.insertFromURL(url("https://CTRL.example.com:1280/edge/client/v1"), store, at: 0))
            XCTAssertNoThrow(try zids.insertFromURL(url("https://ctrl.example.com:443"), store, at: 0), "other port")
            XCTAssertEqual(store.loadAll().0?.count, 2, "nothing stored for the refused one")

            // once enrolled, the controller can be added again
            zids.forEach { $0.enrolled = true }
            XCTAssertNoThrow(try zids.insertFromURL(url("https://ctrl.example.com:1280"), store, at: 0))
        }
    }

    func testInsertFromJWTRefusesAnotherPendingNetworkJwt() throws {
        try withStore { store in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("EnrollmentLinkTests-jwt-\(UUID().uuidString)")
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            var zids:[ZitiIdentity] = []
            XCTAssertNoThrow(try zids.insertFromJWT(jwtFile(makeNetworkJwt(), in: dir), store, at: 0))
            XCTAssertThrowsError(try zids.insertFromJWT(jwtFile(makeNetworkJwt(), in: dir), store, at: 0))
            // a URL identity for the same controller is enrolled differently, so it doesn't count
            XCTAssertNoThrow(try zids.insertFromURL(url("https://ctrl.example.com:443/"), store, at: 0))
            XCTAssertEqual(zids.count, 2)
        }
    }

    func testInsertFromLinkRefusesAnotherPending() throws {
        try withStore { store in
            var zids:[ZitiIdentity] = []
            XCTAssertNoThrow(try zids.insertFromLink(link("ziti://enroll?controller=https://ctrl.example.com")!, store, at: 0))
            XCTAssertThrowsError(try zids.insertFromLink(link("ziti://enroll?controller=https://ctrl.example.com:443")!, store, at: 0))
            XCTAssertNoThrow(try zids.insertFromLink(link("ziti://enroll?jwt=\(makeNetworkJwt())")!, store, at: 0))
            XCTAssertThrowsError(try zids.insertFromLink(link("ziti://enroll?jwt=\(makeNetworkJwt())")!, store, at: 0))
            XCTAssertEqual(zids.count, 2)
        }
    }
}
