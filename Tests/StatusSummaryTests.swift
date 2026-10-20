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

final class StatusSummaryTests: XCTestCase {

    func testNoIdentities() {
        let text = StatusSummary.text(version: "Ziti Version: 2.60 (0), OS: 26.5", status: .disconnected, config: nil, zids: [])
        XCTAssertEqual(text, """
            ======= Status ==========
            Ziti Version: 2.60 (0), OS: 26.5
            Tunnel: Disconnected
            Tunnel settings: None saved
            Identities: 0

            """)
    }

    func testIdentity() {
        let zid = makeIdentity(id: "id1", ztAPI: "https://ctrl.example.com:443", name: "laptop",
                               enrolled: true, enabled: true, enrollTo: "cert",
                               services: [["name": "svc1", "id": "s1"], ["name": "svc2", "id": "s2"]])
        zid.controllerVersion = "v1.6.0"
        zid.edgeStatus = ZitiIdentity.EdgeStatus(0, status: .Available)

        let config:ProviderConfigDict = ["mtu": "4000", "locked": true, "dns": "100.64.0.2"]
        let text = StatusSummary.text(version: "v", status: .connected, config: config, zids: [zid])
        XCTAssertEqual(text, """
            ======= Status ==========
            v
            Tunnel: Connected
            Tunnel settings: Locked by an installed profile
              dns: 100.64.0.2
              locked: true
              mtu: 4000
            Identities: 1

            Identity: laptop [id1]
              Controllers: https://ctrl.example.com:443
              Controller version: v1.6.0
              Enrollment: Enrolled (Device Certificate)
              Enabled: true
              Edge: Available
              Services: 2

            """)
    }

    func testUnknownsAndMfa() {
        let pending = makeIdentity(id: "id2", name: "phone", mfaEnabled: true, mfaVerified: false, mfaPending: true)
        let verified = makeIdentity(id: "id3", name: "tablet", mfaEnabled: true, mfaVerified: true)

        let text = StatusSummary.text(version: "v", status: .connecting, config: [:], zids: [pending, verified])
        XCTAssertTrue(text.contains("Tunnel: Connecting\nTunnel settings: Editable\nIdentities: 2\n"))
        XCTAssertTrue(text.contains("""
            Identity: phone [id2]
              Controllers: https://ctrl.example.com
              Controller version: --
              Enrollment: Pending
              Enabled: false
              Edge: --
              MFA: Not verified, pending
              Services: 0
            """))
        XCTAssertTrue(text.contains("  MFA: Verified\n"))
    }

    func testInvalidSettingsListedAsStored() {
        let config:ProviderConfigDict = ["mtu": "abc", "locked": "yes"]
        let text = StatusSummary.text(version: "v", status: .invalid, config: config, zids: [])
        XCTAssertTrue(text.contains("""
            Tunnel settings: Locked by an installed profile
              locked: yes
              mtu: abc
            Identities: 0
            """))
    }

    // Saved settings come back from preferences as NSNumber, not Swift Bool or Int
    func testSavedNumbersListed() {
        let config:ProviderConfigDict = ["locked": kCFBooleanTrue as NSNumber, "lowPowerMode": kCFBooleanFalse as NSNumber, "mtu": NSNumber(value: 1)]
        let text = StatusSummary.text(version: "v", status: .connected, config: config, zids: [])
        XCTAssertTrue(text.contains("""
            Tunnel settings: Locked by an installed profile
              locked: true
              lowPowerMode: false
              mtu: 1
            Identities: 0
            """))
    }

    func testStatusDescription() {
        XCTAssertEqual(StatusSummary.statusDescription(.invalid), "Invalid")
        XCTAssertEqual(StatusSummary.statusDescription(.reasserting), "Reasserting")
        XCTAssertEqual(StatusSummary.statusDescription(.disconnecting), "Disconnecting")
    }

    func testCanDump() {
        XCTAssertTrue(StatusSummary.canDump(.connecting))
        XCTAssertTrue(StatusSummary.canDump(.connected))
        XCTAssertTrue(StatusSummary.canDump(.reasserting))
        XCTAssertFalse(StatusSummary.canDump(.disconnecting))
        XCTAssertFalse(StatusSummary.canDump(.disconnected))
        XCTAssertFalse(StatusSummary.canDump(.invalid))
    }
}
