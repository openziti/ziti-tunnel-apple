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

class ArrayZitiIdentityTests: XCTestCase {

    // MARK: - updateIdentity

    func testUpdateIdentity_insertsNewAtBeginning() {
        var arr: [ZitiIdentity] = [makeIdentity(id: "existing", name: "Existing")]
        let newZid = makeIdentity(id: "new-id", name: "New")
        arr.updateIdentity(newZid)
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr[0].id, "new-id")
        XCTAssertEqual(arr[1].id, "existing")
    }

    func testUpdateIdentity_updatesExistingById() {
        var arr: [ZitiIdentity] = [
            makeIdentity(id: "id-1", name: "Original")
        ]
        let updated = makeIdentity(id: "id-1", name: "Updated")
        arr.updateIdentity(updated)
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0].name, "Updated")
    }

    func testUpdateIdentity_updatesCorrectElement() {
        var arr: [ZitiIdentity] = [
            makeIdentity(id: "id-1", name: "First"),
            makeIdentity(id: "id-2", name: "Second"),
            makeIdentity(id: "id-3", name: "Third")
        ]
        let updated = makeIdentity(id: "id-2", name: "Updated Second")
        arr.updateIdentity(updated)
        XCTAssertEqual(arr.count, 3)
        XCTAssertEqual(arr[0].name, "First")
        XCTAssertEqual(arr[1].name, "Updated Second")
        XCTAssertEqual(arr[2].name, "Third")
    }

    func testUpdateIdentity_insertsIntoEmptyArray() {
        var arr: [ZitiIdentity] = []
        arr.updateIdentity(makeIdentity(id: "new"))
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0].id, "new")
    }

    // MARK: - getZidIndx

    func testGetZidIndx_findsById() {
        let arr: [ZitiIdentity] = [
            makeIdentity(id: "id-0"),
            makeIdentity(id: "id-1"),
            makeIdentity(id: "id-2")
        ]
        XCTAssertEqual(arr.getZidIndx("id-0"), 0)
        XCTAssertEqual(arr.getZidIndx("id-1"), 1)
        XCTAssertEqual(arr.getZidIndx("id-2"), 2)
    }

    func testGetZidIndx_returnsNegativeOneForNil() {
        let arr: [ZitiIdentity] = [makeIdentity()]
        XCTAssertEqual(arr.getZidIndx(nil), -1)
    }

    func testGetZidIndx_returnsNegativeOneWhenNotFound() {
        let arr: [ZitiIdentity] = [makeIdentity(id: "id-1")]
        XCTAssertEqual(arr.getZidIndx("nonexistent"), -1)
    }

    func testGetZidIndx_emptyArray() {
        let arr: [ZitiIdentity] = []
        XCTAssertEqual(arr.getZidIndx("anything"), -1)
    }

    // MARK: - removeReported

    func testRemoveReported_removesAndReturnsIt() {
        let gone = makeIdentity(id: "id-2", name: "Second")
        var arr: [ZitiIdentity] = [makeIdentity(id: "id-1", name: "First"), gone, makeIdentity(id: "id-3", name: "Third")]
        XCTAssertTrue(arr.removeReported("id-2") === gone)
        XCTAssertEqual(arr.map(\.id), ["id-1", "id-3"], "the others keep their order")
    }

    func testRemoveReported_ignoresIdsNotInTheList() {
        var arr: [ZitiIdentity] = [makeIdentity(id: "id-1", name: "First")]
        XCTAssertNil(arr.removeReported("removed-by-the-app"))
        XCTAssertEqual(arr.count, 1)
    }

    // Enrollment gives an identity its real id by storing it under the new id and removing the temporary file, which
    // the store reports as a removal. The identity is still in the list, as the same object, so nothing is removed
    func testRemoveReported_ignoresTheTemporaryIdAfterEnrollment() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArrayZitiIdentityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TestableZitiIdentityStore(testDir: dir)

        let pending = makeIdentity(id: "temp-id", ztAPI: "https://ctrl.example.com", name: "ctrl.example.com")
        XCTAssertNil(store.store(pending))
        var arr: [ZitiIdentity] = [makeIdentity(id: "other", name: "Other"), pending]

        let resp = CZiti.ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl.example.com"])
        XCTAssertTrue(pending.applyEnrollmentResponse(resp, enrollTo: .token, zidStore: store))
        XCTAssertNil(arr.removeReported("temp-id"))
        XCTAssertEqual(arr.map(\.id), ["other", "real-id"])
        XCTAssertTrue(arr[1] === pending)
    }

    // MARK: - selectionAfterRemoval

    func testSelectionAfterRemoval_followsTheSelectedIdentity() {
        // [id-1, id-2 (selected), id-3] with id-1 removed: id-2 moved up, so the old index would select id-3
        let selected = makeIdentity(id: "id-2", name: "Second")
        let arr: [ZitiIdentity] = [selected, makeIdentity(id: "id-3", name: "Third")]
        XCTAssertEqual(arr.selectionAfterRemoval(selected: selected, at: 1), 0)
    }

    func testSelectionAfterRemoval_takesTheOneInTheRemovedOnesPlace() {
        let arr: [ZitiIdentity] = [makeIdentity(id: "id-1", name: "First"), makeIdentity(id: "id-3", name: "Third")]
        XCTAssertEqual(arr.selectionAfterRemoval(selected: nil, at: 1), 1)
        XCTAssertEqual(arr.selectionAfterRemoval(selected: makeIdentity(id: "id-2", name: "Second"), at: 1), 1,
                       "a selected identity that's no longer listed")
    }

    func testSelectionAfterRemoval_neverPastTheEnd() {
        let arr: [ZitiIdentity] = [makeIdentity(id: "id-1", name: "First")]
        XCTAssertEqual(arr.selectionAfterRemoval(selected: nil, at: 1), 0, "the last one was removed")
    }

    // an identity added later is then read at the selection, which must be a valid index once the list has one
    func testSelectionAfterRemoval_isZeroForAnEmptyList() {
        let arr: [ZitiIdentity] = []
        XCTAssertEqual(arr.selectionAfterRemoval(selected: nil, at: 0), 0)
        XCTAssertEqual(arr.selectionAfterRemoval(selected: nil, at: -1), 0)
    }
}
