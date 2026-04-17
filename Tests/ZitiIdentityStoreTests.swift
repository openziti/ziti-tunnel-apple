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

/// Subclass that redirects file storage to a temp directory
class TestableZitiIdentityStore: ZitiIdentityStore {
    private var _testURL: URL
    override var presentedItemURL: URL? {
        get { _testURL }
        set { if let url = newValue { _testURL = url } }
    }

    init(testDir: URL) {
        _testURL = testDir
        super.init()
    }
}

class ZitiIdentityStoreTests: XCTestCase {

    var testDir: URL!
    var store: TestableZitiIdentityStore!

    override func setUp() {
        super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZitiStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        store = TestableZitiIdentityStore(testDir: testDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
        super.tearDown()
    }

    // MARK: - store + load round-trip

    func testStoreAndLoad() {
        let original = makeIdentity(id: "store-test", name: "Store Test", enrolled: true, enabled: true)
        let storeErr = store.store(original)
        XCTAssertNil(storeErr)

        let (loaded, loadErr) = store.load("store-test")
        XCTAssertNil(loadErr)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "store-test")
        XCTAssertEqual(loaded?.name, "Store Test")
        XCTAssertEqual(loaded?.isEnrolled, true)
        XCTAssertEqual(loaded?.isEnabled, true)
    }

    func testStoreCreatesZidFile() {
        let zid = makeIdentity(id: "file-test")
        _ = store.store(zid)

        let filePath = testDir.appendingPathComponent("file-test.zid")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
    }

    func testStoreOverwritesExisting() {
        let v1 = makeIdentity(id: "overwrite", name: "Version 1")
        _ = store.store(v1)

        let v2 = makeIdentity(id: "overwrite", name: "Version 2")
        _ = store.store(v2)

        let (loaded, _) = store.load("overwrite")
        XCTAssertEqual(loaded?.name, "Version 2")
    }

    // MARK: - load errors

    func testLoad_nonexistentId() {
        let (zid, err) = store.load("does-not-exist")
        XCTAssertNil(zid)
        XCTAssertNotNil(err)
    }

    // MARK: - loadAll

    func testLoadAll_empty() {
        let (zids, err) = store.loadAll()
        XCTAssertNil(err)
        XCTAssertNotNil(zids)
        XCTAssertEqual(zids?.count, 0)
    }

    func testLoadAll_multipleIdentities() {
        _ = store.store(makeIdentity(id: "id-a", name: "Alpha"))
        _ = store.store(makeIdentity(id: "id-b", name: "Beta"))
        _ = store.store(makeIdentity(id: "id-c", name: "Charlie"))

        let (zids, err) = store.loadAll()
        XCTAssertNil(err)
        XCTAssertEqual(zids?.count, 3)

        let ids = Set(zids?.map { $0.id } ?? [])
        XCTAssertEqual(ids, Set(["id-a", "id-b", "id-c"]))
    }

    func testLoadAll_ignoresNonZidFiles() {
        _ = store.store(makeIdentity(id: "real"))

        // Write a non-.zid file
        let otherFile = testDir.appendingPathComponent("notes.txt")
        try! "not a zid".data(using: .utf8)!.write(to: otherFile)

        let (zids, err) = store.loadAll()
        XCTAssertNil(err)
        XCTAssertEqual(zids?.count, 1)
    }

    func testLoadAll_skipsCorruptFiles() {
        _ = store.store(makeIdentity(id: "good"))

        // Write corrupt .zid file
        let corrupt = testDir.appendingPathComponent("bad.zid")
        try! "not json".data(using: .utf8)!.write(to: corrupt)

        let (zids, err) = store.loadAll()
        XCTAssertNil(err)
        XCTAssertEqual(zids?.count, 1)
        XCTAssertEqual(zids?[0].id, "good")
    }

    // MARK: - update with selective options

    func testUpdate_enabledOnly() {
        _ = store.store(makeIdentity(id: "upd", enrolled: false, enabled: false))

        let changed = makeIdentity(id: "upd", enrolled: true, enabled: true)
        _ = store.update(changed, [.Enabled])

        let (loaded, _) = store.load("upd")
        XCTAssertTrue(loaded!.isEnabled)
        XCTAssertFalse(loaded!.isEnrolled, "Enrolled should NOT change when only .Enabled is specified")
    }

    func testUpdate_enrolledOnly() {
        _ = store.store(makeIdentity(id: "upd", enrolled: false, enabled: false))

        let changed = makeIdentity(id: "upd", enrolled: true, enabled: true)
        _ = store.update(changed, [.Enrolled])

        let (loaded, _) = store.load("upd")
        XCTAssertTrue(loaded!.isEnrolled)
        XCTAssertFalse(loaded!.isEnabled, "Enabled should NOT change when only .Enrolled is specified")
    }

    func testUpdate_multipleOptions() {
        _ = store.store(makeIdentity(id: "upd", enrolled: false, enabled: false))

        let changed = makeIdentity(id: "upd", enrolled: true, enabled: true)
        _ = store.update(changed, [.Enabled, .Enrolled])

        let (loaded, _) = store.load("upd")
        XCTAssertTrue(loaded!.isEnabled)
        XCTAssertTrue(loaded!.isEnrolled)
    }

    func testUpdate_edgeStatus() {
        _ = store.store(makeIdentity(id: "upd"))

        let changed = makeIdentity(id: "upd")
        changed.edgeStatus = ZitiIdentity.EdgeStatus(
            Date().timeIntervalSince1970, status: .Available
        )
        _ = store.update(changed, [.EdgeStatus])

        let (loaded, _) = store.load("upd")
        XCTAssertEqual(loaded?.edgeStatus?.status, .Available)
    }

    func testUpdate_controllerVersion() {
        _ = store.store(makeIdentity(id: "upd"))

        let changed = makeIdentity(id: "upd")
        changed.controllerVersion = "v0.35.0"
        _ = store.update(changed, [.ControllerVersion])

        let (loaded, _) = store.load("upd")
        XCTAssertEqual(loaded?.controllerVersion, "v0.35.0")
    }

    func testUpdate_mfa() {
        _ = store.store(makeIdentity(id: "upd"))

        let changed = makeIdentity(id: "upd", mfaEnabled: true, mfaVerified: true, mfaPending: false)
        _ = store.update(changed, [.Mfa])

        let (loaded, _) = store.load("upd")
        XCTAssertTrue(loaded!.isMfaEnabled)
        XCTAssertTrue(loaded!.isMfaVerified)
        XCTAssertFalse(loaded!.isMfaPending)
    }

    func testUpdate_extAuth() {
        _ = store.store(makeIdentity(id: "upd"))

        let changed = makeIdentity(
            id: "upd",
            extAuthPending: true,
            jwtProviders: [["name": "p", "issuer": "i", "canCertEnroll": false, "canTokenEnroll": false]]
        )
        _ = store.update(changed, [.ExtAuth])

        let (loaded, _) = store.load("upd")
        XCTAssertTrue(loaded!.isExtAuthPending)
        XCTAssertTrue(loaded!.isExtAuthEnabled)
    }

    func testUpdate_enrollTo() {
        _ = store.store(makeIdentity(id: "upd", enrolled: true))

        let changed = makeIdentity(id: "upd", enrolled: true, enrollTo: "cert")
        _ = store.update(changed, [.EnrollTo])

        let (loaded, _) = store.load("upd")
        XCTAssertEqual(loaded?.effectiveEnrollTo, .cert)
    }

    func testUpdate_services() {
        _ = store.store(makeIdentity(id: "upd", enrolled: true, enabled: true))

        let svcJSON = makeServiceJSON(name: "new-svc", id: "svc-1", needsRestart: true)
        let changed = makeIdentity(id: "upd", enrolled: true, enabled: true, services: [svcJSON])
        _ = store.update(changed, [.Services])

        let (loaded, _) = store.load("upd")
        XCTAssertEqual(loaded?.services.count, 1)
        XCTAssertEqual(loaded?.services[0].name, "new-svc")
        XCTAssertTrue(loaded!.needsRestart())
    }

    func testUpdate_replace() {
        _ = store.store(makeIdentity(id: "upd", name: "Original", enrolled: false, enabled: false))

        let replacement = makeIdentity(id: "upd", name: "Replaced", enrolled: true, enabled: true, enrollTo: "token")
        _ = store.update(replacement, [.Replace])

        let (loaded, _) = store.load("upd")
        XCTAssertEqual(loaded?.name, "Replaced")
        XCTAssertTrue(loaded!.isEnrolled)
        XCTAssertTrue(loaded!.isEnabled)
        XCTAssertEqual(loaded?.effectiveEnrollTo, .token)
    }

    // MARK: - storeJWT

    func testStoreJWT() {
        let zid = makeIdentity(id: "jwt-test")
        let jwtContent = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.test"
        let jwtSourceURL = testDir.appendingPathComponent("source.jwt")
        try! jwtContent.data(using: .utf8)!.write(to: jwtSourceURL)

        let err = store.storeJWT(zid, jwtSourceURL)
        XCTAssertNil(err)

        let storedPath = testDir.appendingPathComponent("jwt-test.jwt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedPath.path))

        let storedContent = try! String(contentsOf: storedPath, encoding: .utf8)
        XCTAssertEqual(storedContent, jwtContent)
    }

    // MARK: - Delegate

    func testPresentedSubitemDidChange_notifiesDelegate() {
        let delegate = MockStoreDelegate()
        store.delegate = delegate

        let zid = makeIdentity(id: "delegate-test", name: "Delegate Test")
        _ = store.store(zid)

        let url = testDir.appendingPathComponent("delegate-test.zid")
        store.presentedSubitemDidChange(at: url)

        XCTAssertEqual(delegate.newOrChangedIds.count, 1)
        XCTAssertEqual(delegate.newOrChangedIds[0].id, "delegate-test")
    }

    func testPresentedSubitemDidChange_notifiesRemovalForMissingFile() {
        let delegate = MockStoreDelegate()
        store.delegate = delegate

        let url = testDir.appendingPathComponent("gone.zid")
        store.presentedSubitemDidChange(at: url)

        XCTAssertEqual(delegate.removedIds, ["gone"])
    }

    func testPresentedSubitemDidChange_ignoresNonZidFiles() {
        let delegate = MockStoreDelegate()
        store.delegate = delegate

        let url = testDir.appendingPathComponent("notes.txt")
        store.presentedSubitemDidChange(at: url)

        XCTAssertEqual(delegate.newOrChangedIds.count, 0)
        XCTAssertEqual(delegate.removedIds.count, 0)
    }
}

// MARK: - Mock Delegate

class MockStoreDelegate: ZitiIdentityStoreDelegate {
    var newOrChangedIds: [ZitiIdentity] = []
    var removedIds: [String] = []

    func onNewOrChangedId(_ zid: ZitiIdentity) {
        newOrChangedIds.append(zid)
    }

    func onRemovedId(_ idString: String) {
        removedIds.append(idString)
    }
}
