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

    func makeManager(_ providerBundleId:String?, _ name:String, locked:Bool = false) -> NETunnelProviderManager {
        let mgr = NETunnelProviderManager()
        if let providerBundleId = providerBundleId {
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = providerBundleId
            if locked { proto.providerConfiguration = [ProviderConfig.LOCKED_KEY: true] }
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

    func testPreferredManager_noMatch_fallsBackToFirst() {
        // Existing installs must keep using their saved configuration
        let first = makeManager("org.example.other", "first")
        let noProtocol = makeManager(nil, "second")
        XCTAssertTrue(TunnelMgr.preferredManager([first, noProtocol], bid) === first)
    }
}
