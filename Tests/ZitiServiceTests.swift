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

class ZitiServiceTests: XCTestCase {

    // MARK: - postureChecksPassing

    func testPostureChecksPassing_trueWhenOneSetPasses() {
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: false),
            makePQS(isPassing: true)
        ])
        XCTAssertTrue(svc.postureChecksPassing())
    }

    func testPostureChecksPassing_falseWhenAllFail() {
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: false),
            makePQS(isPassing: false)
        ])
        XCTAssertFalse(svc.postureChecksPassing())
    }

    func testPostureChecksPassing_falseWhenNilSets() {
        let svc = makeService()
        XCTAssertFalse(svc.postureChecksPassing())
    }

    func testPostureChecksPassing_falseWhenEmptySets() {
        let svc = makeService(postureQuerySets: [])
        XCTAssertFalse(svc.postureChecksPassing())
    }

    func testPostureChecksPassing_trueWhenOnlySetPasses() {
        let svc = makeService(postureQuerySets: [makePQS(isPassing: true)])
        XCTAssertTrue(svc.postureChecksPassing())
    }

    // MARK: - failingPostureChecks

    func testFailingPostureChecks_emptyWhenNilSets() {
        let svc = makeService()
        XCTAssertEqual(svc.failingPostureChecks(), [])
    }

    func testFailingPostureChecks_emptyWhenAllPass() {
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: true, queries: [
                makePQ(isPassing: true, queryType: "OS")
            ])
        ])
        XCTAssertEqual(svc.failingPostureChecks(), [])
    }

    func testFailingPostureChecks_returnsFailingQueryTypes() {
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: false, queries: [
                makePQ(isPassing: false, queryType: "OS"),
                makePQ(isPassing: true, queryType: "MAC")
            ])
        ])
        XCTAssertEqual(svc.failingPostureChecks(), ["OS"])
    }

    func testFailingPostureChecks_multipleFailingTypes() {
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: false, queries: [
                makePQ(isPassing: false, queryType: "OS"),
                makePQ(isPassing: false, queryType: "MAC")
            ])
        ])
        let fails = Set(svc.failingPostureChecks())
        XCTAssertEqual(fails, Set(["OS", "MAC"]))
    }

    func testFailingPostureChecks_deduplicatesAcrossSets() {
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: false, queries: [makePQ(isPassing: false, queryType: "OS")]),
            makePQS(isPassing: false, queries: [makePQ(isPassing: false, queryType: "OS")])
        ])
        XCTAssertEqual(svc.failingPostureChecks(), ["OS"])
    }

    func testFailingPostureChecks_skipsPassingSets() {
        // Passing sets are not checked for individual failing queries
        let svc = makeService(postureQuerySets: [
            makePQS(isPassing: true, queries: [
                makePQ(isPassing: false, queryType: "OS")  // in passing set, should be ignored
            ]),
            makePQS(isPassing: false, queries: [
                makePQ(isPassing: false, queryType: "MAC")
            ])
        ])
        XCTAssertEqual(svc.failingPostureChecks(), ["MAC"])
    }
}
