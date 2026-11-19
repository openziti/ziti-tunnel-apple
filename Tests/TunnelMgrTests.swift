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
import NetworkExtension
@testable import Ziti_Desktop_Edge

class TunnelMgrTests: XCTestCase {

    let bid = "org.openziti.test.ptp"

    func makeManager(_ providerBundleId:String?, _ name:String, locked:Bool = false, allowedCAs:[String]? = nil) -> NETunnelProviderManager {
        let mgr = NETunnelProviderManager()
        if let providerBundleId = providerBundleId {
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = providerBundleId
            if locked || allowedCAs != nil {
                var conf = ProviderConfig().createDictionary()
                if locked { conf[ProviderConfig.LOCKED_KEY] = true }
                if let allowedCAs = allowedCAs { conf[ProviderConfig.ALLOWED_CAS_KEY] = allowedCAs }
                proto.providerConfiguration = conf
            }
            mgr.protocolConfiguration = proto
        }
        mgr.localizedDescription = name
        return mgr
    }

    func testPreferredManager_empty_returnsNil() {
        XCTAssertNil(TunnelMgr.preferredManager([], bid))
    }

    func testPreferredManager_singleMatch_returnsIt() {
        let mgr = makeManager(bid, "ours")
        XCTAssertTrue(TunnelMgr.preferredManager([mgr], bid) === mgr)
    }

    func testPreferredManager_skipsNonMatching() {
        let other = makeManager("org.example.other", "other")
        let ours = makeManager(bid, "ours")
        XCTAssertTrue(TunnelMgr.preferredManager([other, ours], bid) === ours)
    }

    func testPreferredManager_multipleMatches_returnsFirstMatch() {
        let first = makeManager(bid, "first")
        let second = makeManager(bid, "second")
        XCTAssertTrue(TunnelMgr.preferredManager([first, second], bid) === first)
    }

    func testPreferredManager_multipleMatches_prefersLocked() {
        let first = makeManager(bid, "first")
        let locked = makeManager(bid, "locked", locked: true)
        XCTAssertTrue(TunnelMgr.preferredManager([first, locked], bid) === locked)
    }

    func testPreferredManager_lockedNonMatching_ignored() {
        let other = makeManager("org.example.other", "other", locked: true)
        let ours = makeManager(bid, "ours")
        XCTAssertTrue(TunnelMgr.preferredManager([other, ours], bid) === ours)
    }

    func testIsLocked() {
        XCTAssertFalse(TunnelMgr.isLocked(nil))
        XCTAssertFalse(TunnelMgr.isLocked(makeManager(nil, "none")))
        XCTAssertFalse(TunnelMgr.isLocked(makeManager(bid, "ours")))
        XCTAssertTrue(TunnelMgr.isLocked(makeManager(bid, "ours", locked: true)))
    }

    func testSupersededManagers_lockedPreferred_returnsUnlockedMatches() {
        let ours = makeManager(bid, "ours")
        let locked = makeManager(bid, "locked", locked: true)
        let other = makeManager("org.example.other", "other")
        let superseded = TunnelMgr.supersededManagers([ours, locked, other], locked, bid)
        XCTAssertEqual(superseded.count, 1)
        XCTAssertTrue(superseded.first === ours)
    }

    func testSupersededManagers_unlockedPreferred_returnsNone() {
        // Without a locked config nothing is removed, so existing installs are untouched
        let first = makeManager(bid, "first")
        let second = makeManager(bid, "second")
        XCTAssertTrue(TunnelMgr.supersededManagers([first, second], first, bid).isEmpty)
    }

    func testSupersededManagers_keepsOtherLocked() {
        let locked = makeManager(bid, "locked", locked: true)
        let locked2 = makeManager(bid, "locked2", locked: true)
        XCTAssertTrue(TunnelMgr.supersededManagers([locked, locked2], locked, bid).isEmpty)
    }

    func testPreferredManager_activeUnlocked_beatsLocked() {
        // The running tunnel must stay controllable until it disconnects
        let ours = makeManager(bid, "ours")
        let locked = makeManager(bid, "locked", locked: true)
        let preferred = TunnelMgr.preferredManager([locked, ours], bid) { $0 === ours ? .connected : .disconnected }
        XCTAssertTrue(preferred === ours)
        XCTAssertTrue(TunnelMgr.lockedPending([locked, ours], ours, bid))
    }

    func testLockedPending_falseWhenLockedPreferredOrAbsent() {
        let ours = makeManager(bid, "ours")
        let locked = makeManager(bid, "locked", locked: true)
        XCTAssertFalse(TunnelMgr.lockedPending([locked, ours], locked, bid))
        XCTAssertFalse(TunnelMgr.lockedPending([ours], ours, bid))
    }

    func testLockedPendingRestricts_onlyWithAllowedCAs() {
        // A locked configuration that restricts networks takes over now, not when the user gets around to disconnecting
        let fp = String(repeating: "ab", count: 32)
        let ours = makeManager(bid, "ours")
        let restricting = makeManager(bid, "restricting", locked: true, allowedCAs: [fp])
        let locked = makeManager(bid, "locked", locked: true)
        XCTAssertTrue(TunnelMgr.lockedPendingRestricts([restricting, ours], ours, bid))
        XCTAssertTrue(TunnelMgr.lockedPendingRestricts([ours, locked, restricting], ours, bid))
        XCTAssertFalse(TunnelMgr.lockedPendingRestricts([locked, ours], ours, bid), "locked without allowedCAs waits for a disconnect")
        XCTAssertFalse(TunnelMgr.lockedPendingRestricts([restricting, ours], restricting, bid), "already in use")
        XCTAssertFalse(TunnelMgr.lockedPendingRestricts([ours], ours, bid))
    }

    func testLockedPendingRestricts_ignoresUnusableOrUnlocked() {
        let fp = String(repeating: "ab", count: 32)
        let ours = makeManager(bid, "ours")
        let unlocked = makeManager(bid, "unlocked", allowedCAs: [fp])
        let invalid = makeManager(bid, "invalid")
        (invalid.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration =
            [ProviderConfig.LOCKED_KEY: true, ProviderConfig.ALLOWED_CAS_KEY: [fp]]
        let other = makeManager("org.example.other", "other", locked: true, allowedCAs: [fp])
        XCTAssertFalse(TunnelMgr.lockedPendingRestricts([unlocked, ours], ours, bid))
        XCTAssertFalse(TunnelMgr.lockedPendingRestricts([invalid, ours], ours, bid))
        XCTAssertFalse(TunnelMgr.lockedPendingRestricts([other, ours], ours, bid))
    }

    func testSupersededManagers_keepsActive() {
        let ours = makeManager(bid, "ours")
        let locked = makeManager(bid, "locked", locked: true)
        let superseded = TunnelMgr.supersededManagers([ours, locked], locked, bid) { $0 === ours ? .connecting : .disconnected }
        XCTAssertTrue(superseded.isEmpty)
    }

    func testPreferredManager_invalidLocked_ignored() {
        // A broken profile must not displace a working config
        let ours = makeManager(bid, "ours")
        let invalid = makeManager(bid, "invalid")
        (invalid.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration = [ProviderConfig.LOCKED_KEY: true]
        XCTAssertTrue(TunnelMgr.preferredManager([invalid, ours], bid) === ours)
        XCTAssertTrue(TunnelMgr.preferredManager([ours, invalid], bid) === ours)
        XCTAssertTrue(TunnelMgr.preferredManager([invalid], bid) === invalid) // only option, reports its config error
        XCTAssertTrue(TunnelMgr.supersededManagers([ours, invalid], invalid, bid).isEmpty)
        XCTAssertFalse(TunnelMgr.lockedPending([ours, invalid], ours, bid))
    }

    func testSavePreferences_locked_refusesWithoutSaving() {
        var saveError:Error?
        TunnelMgr.shared.savePreferences(makeManager(bid, "locked", locked: true)) { saveError = $0 }
        XCTAssertNotNil(saveError) // reported synchronously, before any system call
    }

    func testLogSettings() {
        let configured:TunnelMgr.LogSettings = (.INFO, false)
        let session:TunnelMgr.LogSettings = (.TRACE, true)
        XCTAssertEqual(TunnelMgr.logSettings(configured, session: session, locked: true).level, .TRACE)
        XCTAssertTrue(TunnelMgr.logSettings(configured, session: session, locked: true).tlsuv)
        XCTAssertEqual(TunnelMgr.logSettings(configured, session: nil, locked: true).level, .INFO)
        // Unlocked changes are saved, so the configuration is current
        XCTAssertEqual(TunnelMgr.logSettings(configured, session: session, locked: false).level, .INFO)
        XCTAssertFalse(TunnelMgr.logSettings(configured, session: session, locked: false).tlsuv)
    }

    func testStartAction() {
        XCTAssertEqual(TunnelMgr.startAction(enabled: true, locked: false, status: .disconnected), .start)
        XCTAssertEqual(TunnelMgr.startAction(enabled: true, locked: true, status: .disconnected), .start)
        XCTAssertEqual(TunnelMgr.startAction(enabled: false, locked: false, status: .disconnected), .saveAndStart)
        XCTAssertEqual(TunnelMgr.startAction(enabled: false, locked: true, status: .disconnected), .lockedDisabled)
        // Removed configuration
        XCTAssertEqual(TunnelMgr.startAction(enabled: true, locked: false, status: .invalid), .saveAndStart)
        XCTAssertEqual(TunnelMgr.startAction(enabled: true, locked: true, status: .invalid), .createDefault)
    }

    func testPreferredManager_noMatch_fallsBackToFirst() {
        // Existing installs must keep using their saved configuration
        let first = makeManager("org.example.other", "first")
        let noProtocol = makeManager(nil, "second")
        XCTAssertTrue(TunnelMgr.preferredManager([first, noProtocol], bid) === first)
    }

    func testDisconnectAction() {
        typealias Action = TunnelMgr.DisconnectAction
        XCTAssertEqual(TunnelMgr.disconnectAction(restarting: true, lockedPending: true), Action.switchToLocked(start: true))
        XCTAssertEqual(TunnelMgr.disconnectAction(restarting: false, lockedPending: true), Action.switchToLocked(start: false))
        XCTAssertEqual(TunnelMgr.disconnectAction(restarting: true, lockedPending: false), Action.restart)
        XCTAssertEqual(TunnelMgr.disconnectAction(restarting: false, lockedPending: false), Action.none)
    }

    func testEnrollmentPolicy() {
        let policy = CABundlePolicy([String(repeating: "ab", count: 32)])
        XCTAssertEqual(TunnelMgr.enrollmentPolicy(loaded: false, nil), .unknown)
        XCTAssertEqual(TunnelMgr.enrollmentPolicy(loaded: false, policy), .unknown)
        XCTAssertEqual(TunnelMgr.enrollmentPolicy(loaded: true, nil), .unrestricted)
        XCTAssertEqual(TunnelMgr.enrollmentPolicy(loaded: true, policy), .restricted(policy))
    }
}
