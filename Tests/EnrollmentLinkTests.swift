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

final class EnrollmentLinkTests: XCTestCase {

    private func jwt(_ claims:[String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).c2ln"
    }

    private func networkJwt(_ iss:String = "https://ctrl.example.com:443/") -> String {
        return jwt(["iss": iss, "sub": iss, "em": "network"])
    }

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
        let token = networkJwt()
        let l = link("ziti://enroll?jwt=\(token)")
        XCTAssertEqual(l?.source, .jwt(token))
        XCTAssertEqual(l?.controllerName, "ctrl.example.com:443")
    }

    func testRejectsOneTimeTokens() {
        XCTAssertNil(link("ziti://enroll?jwt=\(jwt(["iss": "https://ctrl.example.com", "sub": "abc", "em": "ott"]))"))
        XCTAssertNil(link("ziti://enroll?jwt=\(jwt(["iss": "https://ctrl.example.com", "sub": "abc", "em": "ottca"]))"))
        XCTAssertNil(link("ziti://enroll?jwt=\(jwt(["iss": "https://ctrl.example.com", "sub": "abc"]))"))
    }

    func testHints() {
        let l = link("ziti://enroll?controller=https://ctrl.example.com&provider=alpha&type=cert")
        XCTAssertEqual(l?.hint, Enrollment.Hint(provider: "alpha", enrollTo: .cert))
        XCTAssertEqual(link("ziti://enroll?jwt=\(networkJwt())&type=token")?.hint, Enrollment.Hint(provider: nil, enrollTo: .token))
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
        XCTAssertNil(link("ziti://enroll?controller=https://ctrl.example.com&jwt=\(networkJwt())"))
    }

    func testRejectsNonHttpsController() {
        XCTAssertNil(link("ziti://enroll?controller=http://ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?controller=ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?controller=https://user@ctrl.example.com"))
        XCTAssertNil(link("ziti://enroll?jwt=\(networkJwt("http://ctrl.example.com"))"))
    }

    func testRejectsMalformedJwt() {
        XCTAssertNil(link("ziti://enroll?jwt=not-a-jwt"))
        XCTAssertNil(link("ziti://enroll?jwt=a.b.c"))
        XCTAssertNil(link("ziti://enroll?jwt=\(jwt(["em": "network"]))"))
    }

    func testRedacted() {
        XCTAssertEqual(EnrollmentLink.redacted(URL(string: "ziti://enroll?jwt=\(networkJwt())#x")!), "ziti://enroll")
        XCTAssertEqual(EnrollmentLink.redacted(URL(string: "https://ctrl.example.com:1280/path")!), "https://ctrl.example.com:1280/path")
    }
}
