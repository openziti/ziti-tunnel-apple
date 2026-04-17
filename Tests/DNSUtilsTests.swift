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

class DNSUtilsTests: XCTestCase {

    var entries: DNSUtils.DnsEntries!

    override func setUp() {
        super.setUp()
        entries = DNSUtils.DnsEntries()
    }

    // MARK: - add

    func testAdd_singleEntry() {
        entries.add("example.ziti", "100.64.0.1", "svc-1")
        XCTAssertEqual(entries.entries.count, 1)
        XCTAssertEqual(entries.entries[0].hostname, "example.ziti")
        XCTAssertEqual(entries.entries[0].ip, "100.64.0.1")
        XCTAssertEqual(entries.entries[0].serviceIds, ["svc-1"])
    }

    func testAdd_duplicateHostname_appendsServiceId() {
        entries.add("example.ziti", "100.64.0.1", "svc-1")
        entries.add("example.ziti", "100.64.0.1", "svc-2")
        XCTAssertEqual(entries.entries.count, 1)
        XCTAssertEqual(entries.entries[0].serviceIds, ["svc-1", "svc-2"])
    }

    func testAdd_duplicateHostname_caseInsensitive() {
        entries.add("Example.Ziti", "100.64.0.1", "svc-1")
        entries.add("EXAMPLE.ZITI", "100.64.0.1", "svc-2")
        XCTAssertEqual(entries.entries.count, 1)
        XCTAssertEqual(entries.entries[0].serviceIds, ["svc-1", "svc-2"])
    }

    func testAdd_differentHostnames() {
        entries.add("one.ziti", "100.64.0.1", "svc-1")
        entries.add("two.ziti", "100.64.0.2", "svc-2")
        XCTAssertEqual(entries.entries.count, 2)
    }

    func testAdd_hostnameStoredLowercase() {
        entries.add("MyHost.Ziti", "100.64.0.1", "svc-1")
        XCTAssertEqual(entries.entries[0].hostname, "myhost.ziti")
    }

    // MARK: - remove

    func testRemove_removesServiceId() {
        entries.add("example.ziti", "100.64.0.1", "svc-1")
        entries.add("example.ziti", "100.64.0.1", "svc-2")
        entries.remove("svc-1")
        XCTAssertEqual(entries.entries.count, 1)
        XCTAssertEqual(entries.entries[0].serviceIds, ["svc-2"])
    }

    func testRemove_dropsEntryWhenNoServiceIds() {
        entries.add("example.ziti", "100.64.0.1", "svc-1")
        entries.remove("svc-1")
        XCTAssertEqual(entries.entries.count, 0)
    }

    func testRemove_onlyAffectsMatchingServiceId() {
        entries.add("one.ziti", "100.64.0.1", "svc-1")
        entries.add("two.ziti", "100.64.0.2", "svc-2")
        entries.remove("svc-1")
        XCTAssertEqual(entries.entries.count, 1)
        XCTAssertEqual(entries.entries[0].hostname, "two.ziti")
    }

    func testRemove_nonexistentServiceId_noEffect() {
        entries.add("example.ziti", "100.64.0.1", "svc-1")
        entries.remove("svc-999")
        XCTAssertEqual(entries.entries.count, 1)
    }

    // MARK: - contains

    func testContains_matchesExact() {
        entries.add("Example.Ziti", "100.64.0.1", "svc-1")
        // hostname is stored lowercase
        XCTAssertTrue(entries.contains("example.ziti"))
    }

    func testContains_noMatch() {
        entries.add("example.ziti", "100.64.0.1", "svc-1")
        XCTAssertFalse(entries.contains("other.ziti"))
    }

    func testContains_empty() {
        XCTAssertFalse(entries.contains("anything"))
    }

    func testContains_caseSensitiveLookup() {
        // contains uses == which is case-sensitive; hostnames are stored lowercase
        entries.add("Example.Ziti", "100.64.0.1", "svc-1")
        XCTAssertFalse(entries.contains("Example.Ziti"))
        XCTAssertTrue(entries.contains("example.ziti"))
    }

    // MARK: - hostnames

    func testHostnames_returnsAll() {
        entries.add("alpha.ziti", "100.64.0.1", "svc-1")
        entries.add("beta.ziti", "100.64.0.2", "svc-2")
        let names = entries.hostnames
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.contains("alpha.ziti"))
        XCTAssertTrue(names.contains("beta.ziti"))
    }

    func testHostnames_emptyWhenNoEntries() {
        XCTAssertEqual(entries.hostnames.count, 0)
    }
}
