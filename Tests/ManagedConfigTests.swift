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

/// Defaults with chosen values, some of them forced as managed preferences would be
private class FakeDefaults : UserDefaults {
    var values:[String: Any] = [:]
    var forced:Set<String> = []

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func objectIsForced(forKey key: String) -> Bool { forced.contains(key) }
}

final class ManagedConfigTests: XCTestCase {

    private func networkJwt(_ iss:String = "https://ctrl.example.com:443/", em:String = "network") -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["iss": iss, "sub": iss, "em": em])
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJSUzI1NiJ9.\(payload).c2ln"
    }

    private func config(_ networks:Any) -> ManagedConfig? {
        return ManagedConfig([ManagedConfig.NETWORKS_KEY: networks])
    }

    private func identity(_ ztAPIs:[String], enrolled:Bool = false) -> ZitiIdentity {
        let zid = ZitiIdentity()
        zid.czid = CZiti.ZitiIdentity(id: UUID().uuidString, ztAPIs: ztAPIs)
        zid.enrolled = enrolled
        return zid
    }

    // MARK: - Parsing

    func testNoKeysMeansNoConfig() {
        XCTAssertNil(ManagedConfig([:]))
        XCTAssertNil(ManagedConfig(["other": true]))
    }

    func testNetworks() {
        let cfg = config([
            ["controller": "https://ctrl.example.com:1280", "provider": "Okta", "type": "cert"],
            ["jwt": networkJwt("https://other.example.com:443/")]
        ])
        XCTAssertEqual(cfg?.networks.count, 2)
        XCTAssertEqual(cfg?.networks.first?.source, .controller(URL(string: "https://ctrl.example.com:1280")!))
        XCTAssertEqual(cfg?.networks.first?.hint, Enrollment.Hint(provider: "Okta", enrollTo: .cert))
        XCTAssertEqual(cfg?.networks.last?.controllerName, "other.example.com:443")
        XCTAssertEqual(cfg?.disableAddIdentity, false)
        XCTAssertEqual(cfg?.disableRemoveIdentity, false)
    }

    func testSameAsEnrollmentLink() {
        let jwt = networkJwt()
        let link = EnrollmentLink(URL(string: "ziti://enroll?jwt=\(jwt)&provider=Okta&type=token")!)
        XCTAssertNotNil(link)
        XCTAssertEqual(config([["jwt": jwt, "provider": "Okta", "type": "token"]])?.networks, [link!])
    }

    func testInvalidNetworksAreSkipped() {
        let valid = ["controller": "https://ctrl.example.com"]
        let cfg = config([
            ["controller": "https://a.example.com", "jwt": networkJwt()],   // both
            ["provider": "Okta"],                                           // neither
            ["controller": "http://b.example.com"],                         // not https
            ["jwt": networkJwt(em: "ott")],                                 // one-time token
            ["controller": "https://c.example.com", "type": "password"],    // unknown type
            ["controller": "https://d.example.com", "provider": 1],         // wrong field type
            "https://e.example.com",                                        // not a dictionary
            valid
        ] as [Any])
        XCTAssertEqual(cfg?.networks.map(\.controllerName), ["ctrl.example.com"])
    }

    func testNetworksNotAList() {
        XCTAssertEqual(config(["controller": "https://ctrl.example.com"])?.networks, [])
        XCTAssertEqual(config([])?.networks, [])
    }

    func testDuplicateControllerFirstWins() {
        let cfg = config([
            ["controller": "https://ctrl.example.com", "provider": "first"],
            ["controller": "https://CTRL.example.com:443/", "provider": "second"],
            ["controller": "https://ctrl.example.com:1280"]
        ])
        XCTAssertEqual(cfg?.networks.map(\.hint.provider), ["first", nil])
    }

    func testRestrictions() {
        for value in [true, 1, "true", "YES"] as [Any] {
            let cfg = ManagedConfig([ManagedConfig.DISABLE_ADD_IDENTITY_KEY: value, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: value])
            XCTAssertEqual(cfg?.disableAddIdentity, true, "\(value)")
            XCTAssertEqual(cfg?.disableRemoveIdentity, true, "\(value)")
            XCTAssertEqual(cfg?.networks, [])
        }
        XCTAssertEqual(ManagedConfig([ManagedConfig.DISABLE_ADD_IDENTITY_KEY: false])?.disableAddIdentity, false)
        XCTAssertEqual(ManagedConfig([ManagedConfig.DISABLE_ADD_IDENTITY_KEY: "maybe"])?.disableAddIdentity, false)
    }

    func testDescription() {
        XCTAssertEqual(config([["controller": "https://ctrl.example.com"]])?.description, "1 network")
        let cfg = ManagedConfig([ManagedConfig.DISABLE_ADD_IDENTITY_KEY: true, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: true])
        XCTAssertEqual(cfg?.description, "0 networks, adding identities turned off, removing managed identities turned off")
    }

    // MARK: - Reading

#if os(macOS)
    func testOnlyForcedValuesCountOnMacOS() {
        let defaults = FakeDefaults(suiteName: "ManagedConfigTests")!
        defaults.values = [ManagedConfig.DISABLE_ADD_IDENTITY_KEY: true, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: true]
        defaults.forced = [ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY]

        let cfg = ManagedConfig.current(defaults)
        XCTAssertEqual(cfg?.disableAddIdentity, false)
        XCTAssertEqual(cfg?.disableRemoveIdentity, true)

        defaults.forced = []
        XCTAssertNil(ManagedConfig.current(defaults))
    }
#endif

    // MARK: - Identities

    func testIsManagedMatchesHostAndPort() {
        let cfg = config([["controller": "https://ctrl.example.com"], ["jwt": networkJwt("https://other.example.com:1280")]])!
        XCTAssertTrue(cfg.isManaged(identity(["https://ctrl.example.com:443/edge/client/v1"], enrolled: true)))
        XCTAssertTrue(cfg.isManaged(identity(["https://OTHER.example.com:1280"])))
        XCTAssertTrue(cfg.isManaged(identity(["https://ha1.example.com", "https://ctrl.example.com"])))
        XCTAssertFalse(cfg.isManaged(identity(["https://ctrl.example.com:1280"])))
        XCTAssertFalse(cfg.isManaged(identity(["https://ctrl.example.com.evil.example"])))
    }

    func testCanRemove() {
        let managed = identity(["https://ctrl.example.com"]), other = identity(["https://other.example.com"])
        let networks = [["controller": "https://ctrl.example.com"]]

        let locked = ManagedConfig([ManagedConfig.NETWORKS_KEY: networks, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: true])!
        XCTAssertFalse(locked.canRemove(managed))
        XCTAssertTrue(locked.canRemove(other))

        XCTAssertTrue(config(networks)!.canRemove(managed))
    }

    func testHint() {
        let cfg = config([["controller": "https://ctrl.example.com", "provider": "Okta", "type": "token"]])!
        XCTAssertEqual(cfg.hint(for: identity(["https://ctrl.example.com:443"])), Enrollment.Hint(provider: "Okta", enrollTo: .token))
        XCTAssertEqual(cfg.hint(for: identity(["https://other.example.com"])), Enrollment.Hint())
    }

    func testInsertManaged() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ManagedConfigTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TestableZitiIdentityStore(testDir: dir)

        let cfg = config([["controller": "https://new.example.com:1280"], ["controller": "https://ctrl.example.com"]])!
        var zids = [identity(["https://ctrl.example.com:443/edge/client/v1"], enrolled: true)]

        XCTAssertEqual(zids.insertManaged(cfg, store), 1)
        XCTAssertEqual(zids.count, 2)
        XCTAssertEqual(zids.first?.czid?.ztAPI, "https://new.example.com:1280")
        XCTAssertFalse(zids.first?.isEnrolled ?? true)
        XCTAssertEqual(store.loadAll().0?.count, 1)

        // pending or enrolled, a network with an identity isn't added again
        XCTAssertEqual(zids.insertManaged(cfg, store), 0)
        XCTAssertEqual(zids.count, 2)
    }

    // MARK: - Restrictions for the share extension

    func testSharedRestrictions() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restrictions-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(SharedRestrictions.isAddIdentityDisabled(at: url))
        SharedRestrictions.save(addIdentityDisabled: true, to: url)
        XCTAssertTrue(SharedRestrictions.isAddIdentityDisabled(at: url))
        SharedRestrictions.save(addIdentityDisabled: false, to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(SharedRestrictions.isAddIdentityDisabled(at: url))
    }
}
