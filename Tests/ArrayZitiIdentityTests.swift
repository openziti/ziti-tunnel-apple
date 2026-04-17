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
}
