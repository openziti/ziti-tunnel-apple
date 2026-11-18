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

    private func config(_ networks:Any) -> ManagedConfig? {
        return ManagedConfig([ManagedConfig.NETWORKS_KEY: networks])
    }

    private func identity(_ ztAPIs:[String], enrolled:Bool = false) -> ZitiIdentity {
        return makeIdentity(id: UUID().uuidString, ztAPI: ztAPIs[0], ztAPIs: ztAPIs, enrolled: enrolled)
    }

    // MARK: - Parsing

    func testNoKeysMeansNoConfig() {
        XCTAssertNil(ManagedConfig([:]))
        XCTAssertNil(ManagedConfig(["other": true]))
    }

    func testNetworks() {
        let cfg = config([
            ["controller": "https://ctrl.example.com:1280", "provider": "Okta", "type": "cert"],
            ["jwt": makeNetworkJwt("https://other.example.com:443/")]
        ])
        XCTAssertEqual(cfg?.networks.count, 2)
        XCTAssertEqual(cfg?.networks.first?.source, .controller(URL(string: "https://ctrl.example.com:1280")!))
        XCTAssertEqual(cfg?.networks.first?.hint, Enrollment.Hint(provider: "Okta", enrollTo: .cert))
        XCTAssertEqual(cfg?.networks.last?.controllerName, "other.example.com:443")
        XCTAssertEqual(cfg?.disableAddIdentity, false)
        XCTAssertEqual(cfg?.disableRemoveIdentity, false)
    }

    func testSameAsEnrollmentLink() {
        let jwt = makeNetworkJwt()
        let link = EnrollmentLink(URL(string: "ziti://enroll?jwt=\(jwt)&provider=Okta&type=token")!)
        XCTAssertNotNil(link)
        XCTAssertEqual(config([["jwt": jwt, "provider": "Okta", "type": "token"]])?.networks, [link!])
    }

    func testInvalidNetworksAreSkipped() {
        let valid = ["controller": "https://ctrl.example.com"]
        let cfg = config([
            ["controller": "https://a.example.com", "jwt": makeNetworkJwt()],   // both
            ["provider": "Okta"],                                           // neither
            ["controller": "http://b.example.com"],                         // not https
            ["jwt": makeNetworkJwt(em: "ott")],                                 // one-time token
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
        XCTAssertEqual(ManagedConfig([ManagedConfig.DISABLE_ADD_IDENTITY_KEY: "no"])?.problems, [])
    }

    func testInvalidRestrictionIsOn() {
        // a mistake doesn't lift a restriction
        for value in ["maybe", "tru", [], ["a": 1]] as [Any] {
            let cfg = ManagedConfig([ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: value])
            XCTAssertEqual(cfg?.disableRemoveIdentity, true, "\(value)")
            XCTAssertEqual(cfg?.problems, ["Invalid managed disableRemoveIdentity, treating it as true"], "\(value)")
        }
    }

    func testProblemsAreCollectedNotLogged() {
        let cfg = ManagedConfig([ManagedConfig.NETWORKS_KEY: [["provider": "Okta"], ["controller": "https://c.example.com"],
                                                              ["controller": "https://C.example.com:443"]],
                                 ManagedConfig.DISABLE_ADD_IDENTITY_KEY: "maybe"])
        XCTAssertEqual(cfg?.problems, ["Ignoring invalid managed network 1",
                                       "Ignoring managed network 3: same controller as an earlier one",
                                       "Invalid managed disableAddIdentity, treating it as true"])
        XCTAssertEqual(ManagedConfig([ManagedConfig.NETWORKS_KEY: "https://c.example.com"])?.problems,
                       ["Ignoring managed networks: not a list"])
    }

    func testDescription() {
        XCTAssertEqual(config([["controller": "https://ctrl.example.com"]])?.description, "1 network")
        let cfg = ManagedConfig([ManagedConfig.DISABLE_ADD_IDENTITY_KEY: true, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: true])
        XCTAssertEqual(cfg?.description, "0 networks, adding identities turned off, removing managed identities turned off")
        XCTAssertEqual(config([["provider": "Okta"], ["controller": "https://c.example.com"]])?.description, "1 network, 1 problem (see the app log)")
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

    func testManagedAppConfiguration() {
        // the iOS source, readable on macOS too
        let suite = "ManagedConfigTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(defaults.managedAppConfiguration)

        defaults.set([ManagedConfig.NETWORKS_KEY: [["controller": "https://ctrl.example.com"]],
                      ManagedConfig.DISABLE_ADD_IDENTITY_KEY: true], forKey: UserDefaults.MANAGED_CONFIGURATION_KEY)
        let cfg = ManagedConfig { defaults.managedAppConfiguration?[$0] }
        XCTAssertEqual(cfg?.networks.count, 1)
        XCTAssertEqual(cfg?.disableAddIdentity, true)

        defaults.set([String: Any](), forKey: UserDefaults.MANAGED_CONFIGURATION_KEY)
        XCTAssertNil(ManagedConfig { defaults.managedAppConfiguration?[$0] })
        defaults.set("not a dictionary", forKey: UserDefaults.MANAGED_CONFIGURATION_KEY)
        XCTAssertNil(defaults.managedAppConfiguration)
    }

    // MARK: - Identities

    func testIsManagedMatchesHostAndPort() {
        let cfg = config([["controller": "https://ctrl.example.com"], ["jwt": makeNetworkJwt("https://other.example.com:1280")]])!
        XCTAssertTrue(cfg.isManaged(identity(["https://ctrl.example.com:443/edge/client/v1"], enrolled: true)))
        XCTAssertTrue(cfg.isManaged(identity(["https://OTHER.example.com:1280"])))
        XCTAssertTrue(cfg.isManaged(identity(["https://ha1.example.com", "https://ctrl.example.com"])))
        XCTAssertFalse(cfg.isManaged(identity(["https://ctrl.example.com:1280"])))
        XCTAssertFalse(cfg.isManaged(identity(["https://ctrl.example.com.evil.example"])))

        let v6 = config([["controller": "https://[2001:db8::1]:1280"]])!
        XCTAssertTrue(v6.isManaged(identity(["https://[2001:db8::1]:1280/edge/client/v1"])))
        XCTAssertFalse(v6.isManaged(identity(["https://[2001:db8::1]:1281"])))
    }

    func testCanEnrollAndNetworkAt() {
        let managed = identity(["https://ctrl.example.com"]), other = identity(["https://other.example.com"])
        let networks = [["controller": "https://ctrl.example.com"]]

        let locked = ManagedConfig([ManagedConfig.NETWORKS_KEY: networks, ManagedConfig.DISABLE_ADD_IDENTITY_KEY: true])!
        XCTAssertTrue(locked.canEnroll(managed))
        XCTAssertFalse(locked.canEnroll(other), "added before adding was turned off")
        XCTAssertTrue(config(networks)!.canEnroll(other))

        XCTAssertEqual(locked.network(at: URL(string: "https://CTRL.example.com:443/edge/client/v1")!), locked.networks[0])
        XCTAssertNil(locked.network(at: URL(string: "https://ctrl.example.com:1280")!))
        XCTAssertNil(locked.network(at: URL(string: "https://other.example.com")!))
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

    private func withStore(_ test:(TestableZitiIdentityStore) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ManagedConfigTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(TestableZitiIdentityStore(testDir: dir))
    }

    func testInsertManagedSameHostOtherPorts() {
        withStore { store in
            var zids:[ZitiIdentity] = []
            let cfg = config([["controller": "https://ctrl.example.com"], ["controller": "https://ctrl.example.com:1280"]])!
            XCTAssertEqual(zids.insertManaged(cfg, store), 2)
            XCTAssertEqual(Set(zids.map(\.id)).count, 2)
            XCTAssertEqual(store.loadAll().0?.count, 2)
        }
    }

    func testInsertManagedNetworkJwt() {
        withStore { store in
            var zids:[ZitiIdentity] = []
            let cfg = config([["jwt": makeNetworkJwt("https://jwt.example.com:1280/")]])!
            XCTAssertEqual(zids.insertManaged(cfg, store), 1)
            XCTAssertEqual(zids.first?.claims?.em, "network")
            XCTAssertTrue(cfg.isManaged(zids[0]))
            XCTAssertEqual(zids.insertManaged(cfg, store), 0)
        }
    }

    /// What a config event does: the controller addresses become the ones the network reports
    private func reportControllers(_ zid:ZitiIdentity, _ ztAPIs:[String]) {
        zid.czid?.ztAPI = ztAPIs[0]
        zid.czid?.ztAPIs = ztAPIs
    }

    func testAddedNetworkStaysManagedWhenControllersChange() {
        withStore { store in
            let cfg = ManagedConfig([ManagedConfig.NETWORKS_KEY: [["controller": "https://ctrl.example.com", "provider": "Okta", "type": "cert"]],
                                     ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY: true])!
            var zids:[ZitiIdentity] = []
            XCTAssertEqual(zids.insertManaged(cfg, store), 1)
            XCTAssertEqual(zids[0].managedController, "https://ctrl.example.com")
            XCTAssertEqual(store.loadAll().0?.first?.managedController, "https://ctrl.example.com", "recorded on disk")

            // enrolled, then the cluster reports its members, none of them the configured address
            zids[0].enrolled = true
            reportControllers(zids[0], ["https://ha1.example.com:443/edge/client/v1", "https://ha2.example.com:443/edge/client/v1"])
            XCTAssertTrue(cfg.isManaged(zids[0]))
            XCTAssertFalse(cfg.canRemove(zids[0]))
            XCTAssertEqual(cfg.hint(for: zids[0]), Enrollment.Hint(provider: "Okta", enrollTo: .cert))
            XCTAssertEqual(zids.insertManaged(cfg, store), 0, "no duplicate")
            XCTAssertEqual(zids.count, 1)
        }
    }

    func testExistingIdentityRecordedAsManaged() {
        withStore { store in
            // added before the configuration, so only its controllers say it's on the managed network
            let zid = identity(["https://ctrl.example.com:443/edge/client/v1"], enrolled: true)
            XCTAssertNil(store.store(zid))
            var zids = [zid]
            let cfg = config([["controller": "https://ctrl.example.com"]])!
            XCTAssertEqual(zids.insertManaged(cfg, store), 0)
            XCTAssertEqual(zid.managedController, "https://ctrl.example.com")
            XCTAssertEqual(store.loadAll().0?.first?.managedController, "https://ctrl.example.com", "recorded on disk")

            reportControllers(zid, ["https://ha1.example.com"])
            XCTAssertTrue(cfg.isManaged(zid))
            XCTAssertEqual(zids.insertManaged(cfg, store), 0)
        }
    }

    func testRecordedNetworkMustStillBeConfigured() {
        let zid = identity(["https://ha1.example.com"], enrolled: true)
        zid.managedController = "https://old.example.com"
        XCTAssertFalse(config([["controller": "https://other.example.com"]])!.isManaged(zid), "dropped from the configuration")
        XCTAssertTrue(config([["controller": "https://OLD.example.com:443"]])!.isManaged(zid), "same host and port")
        XCTAssertTrue(config([["controller": "https://ha1.example.com"]])!.isManaged(zid), "still matched by its controllers")
    }

    func testManagedIdentityAt() throws {
        try withStore { store in
            let cfg = config([["controller": "https://ctrl.example.com"]])!
            var zids:[ZitiIdentity] = []
            XCTAssertNil(try zids.managedIdentity(at: URL(string: "https://other.example.com")!, cfg, store))
            XCTAssertEqual(zids.count, 0, "nothing added for another network")

            let zid = try zids.managedIdentity(at: URL(string: "https://CTRL.example.com:443")!, cfg, store)
            XCTAssertNotNil(zid)
            XCTAssertTrue(cfg.isManaged(zid!))
            XCTAssertEqual(zids.count, 1)
            XCTAssertTrue(try zids.managedIdentity(at: URL(string: "https://ctrl.example.com")!, cfg, store) === zid, "the same one, not another")

            // removed by the user, then added again
            XCTAssertNil(store.remove(zid!))
            zids.removeAll()
            let again = try zids.managedIdentity(at: URL(string: "https://ctrl.example.com")!, cfg, store)
            XCTAssertNotNil(again)
            XCTAssertEqual(store.loadAll().0?.count, 1)
        }
    }

    func testManagedIdentityAtThrowsWhenItCantBeAdded() {
        let store = TestableZitiIdentityStore(testDir: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        var zids:[ZitiIdentity] = []
        let cfg = config([["controller": "https://ctrl.example.com"]])!
        XCTAssertThrowsError(try zids.managedIdentity(at: URL(string: "https://ctrl.example.com")!, cfg, store))
    }

    func testManagedIdentityForJWT() throws {
        try withStore { store in
            let file = { (jwt:String) -> URL in
                let url = store.presentedItemURL!.appendingPathComponent("\(UUID().uuidString).jwt")
                try! jwt.write(to: url, atomically: true, encoding: .utf8)
                return url
            }
            let cfg = config([["controller": "https://ctrl.example.com"]])!
            var zids:[ZitiIdentity] = []
            let zid = try zids.managedIdentity(forJWT: file(makeNetworkJwt()), cfg, store)
            XCTAssertNotNil(zid)
            XCTAssertTrue(cfg.isManaged(zid!))
            XCTAssertNil(try zids.managedIdentity(forJWT: file(makeNetworkJwt(em: "ott")), cfg, store), "a one-time token is its own identity")
            XCTAssertNil(try zids.managedIdentity(forJWT: file(makeNetworkJwt("https://other.example.com/")), cfg, store))
            XCTAssertEqual(zids.count, 1)
        }
    }

    func testInsertManagedKeepsGoingAfterFailure() {
        // a store that can't write: every insert fails, none throws, and each network is tried
        let store = TestableZitiIdentityStore(testDir: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        var zids:[ZitiIdentity] = []
        let cfg = config([["controller": "https://a.example.com"], ["controller": "https://b.example.com"]])!
        XCTAssertEqual(zids.insertManaged(cfg, store), 0)
        XCTAssertEqual(zids.count, 0)
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

    func testSharedRestrictionsMalformedFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restrictions-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }

        try! Data("not a plist".utf8).write(to: url)
        XCTAssertFalse(SharedRestrictions.isAddIdentityDisabled(at: url))
        SharedRestrictions.save(addIdentityDisabled: true, to: url)
        XCTAssertTrue(SharedRestrictions.isAddIdentityDisabled(at: url))

        // only a boolean counts: the app writes one
        try! PropertyListSerialization.data(fromPropertyList: ["disableAddIdentity": "true"], format: .xml, options: 0).write(to: url)
        XCTAssertFalse(SharedRestrictions.isAddIdentityDisabled(at: url))
    }

    func testSharedRestrictionsKeepEachOther() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restrictions-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let policy = CABundlePolicy([String(repeating: "ab", count: 32)])

        XCTAssertNil(SharedRestrictions.caBundlePolicy(at: url))
        SharedRestrictions.save(caBundlePolicy: policy, to: url)
        SharedRestrictions.save(addIdentityDisabled: true, to: url)
        XCTAssertEqual(SharedRestrictions.caBundlePolicy(at: url), policy)
        XCTAssertTrue(SharedRestrictions.isAddIdentityDisabled(at: url))

        // a policy without fingerprints still restricts
        SharedRestrictions.save(caBundlePolicy: CABundlePolicy([]), to: url)
        XCTAssertEqual(SharedRestrictions.caBundlePolicy(at: url)?.fingerprints, [])

        SharedRestrictions.save(addIdentityDisabled: false, to: url)
        XCTAssertNotNil(SharedRestrictions.caBundlePolicy(at: url))
        SharedRestrictions.save(caBundlePolicy: nil, to: url)
        XCTAssertNil(SharedRestrictions.caBundlePolicy(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
