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

class IPUtilsTests: XCTestCase {

    // MARK: - ipV4AddressStringToData

    func testIpV4AddressStringToData_basicAddress() {
        let data = IPUtils.ipV4AddressStringToData("192.168.1.1")
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual([UInt8](data), [192, 168, 1, 1])
    }

    func testIpV4AddressStringToData_zeros() {
        let data = IPUtils.ipV4AddressStringToData("0.0.0.0")
        XCTAssertEqual([UInt8](data), [0, 0, 0, 0])
    }

    func testIpV4AddressStringToData_maxValues() {
        let data = IPUtils.ipV4AddressStringToData("255.255.255.255")
        XCTAssertEqual([UInt8](data), [255, 255, 255, 255])
    }

    func testIpV4AddressStringToData_loopback() {
        let data = IPUtils.ipV4AddressStringToData("127.0.0.1")
        XCTAssertEqual([UInt8](data), [127, 0, 0, 1])
    }

    // MARK: - isValidIpV4Address

    func testIsValidIpV4Address_validAddresses() {
        XCTAssertTrue(IPUtils.isValidIpV4Address("192.168.1.1"))
        XCTAssertTrue(IPUtils.isValidIpV4Address("0.0.0.0"))
        XCTAssertTrue(IPUtils.isValidIpV4Address("255.255.255.255"))
        XCTAssertTrue(IPUtils.isValidIpV4Address("10.0.0.1"))
        XCTAssertTrue(IPUtils.isValidIpV4Address("172.16.0.1"))
    }

    func testIsValidIpV4Address_withWhitespace() {
        XCTAssertTrue(IPUtils.isValidIpV4Address("  192.168.1.1  "))
    }

    func testIsValidIpV4Address_octetOutOfRange() {
        XCTAssertFalse(IPUtils.isValidIpV4Address("256.1.1.1"))
        XCTAssertFalse(IPUtils.isValidIpV4Address("1.1.1.256"))
        XCTAssertFalse(IPUtils.isValidIpV4Address("999.999.999.999"))
    }

    func testIsValidIpV4Address_tooFewOctets() {
        XCTAssertFalse(IPUtils.isValidIpV4Address("1.1.1"))
        XCTAssertFalse(IPUtils.isValidIpV4Address("1.1"))
        XCTAssertFalse(IPUtils.isValidIpV4Address("1"))
    }

    func testIsValidIpV4Address_tooManyOctets() {
        XCTAssertFalse(IPUtils.isValidIpV4Address("1.1.1.1.1"))
    }

    func testIsValidIpV4Address_nonNumeric() {
        XCTAssertFalse(IPUtils.isValidIpV4Address("abc.def.ghi.jkl"))
        XCTAssertFalse(IPUtils.isValidIpV4Address(""))
        XCTAssertFalse(IPUtils.isValidIpV4Address("not an ip"))
    }

    func testIsValidIpV4Address_negativeOctet() {
        XCTAssertFalse(IPUtils.isValidIpV4Address("-1.0.0.0"))
    }

    // MARK: - areSameRoutes

    func testAreSameRoutes_identical() {
        let r1 = NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.255.255.0")
        let r2 = NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.255.255.0")
        XCTAssertTrue(IPUtils.areSameRoutes(r1, r2))
    }

    func testAreSameRoutes_sameNetwork() {
        // Both are in 10.0.0.0/24 - host bits differ but network bits are the same
        let r1 = NEIPv4Route(destinationAddress: "10.0.0.1", subnetMask: "255.255.255.0")
        let r2 = NEIPv4Route(destinationAddress: "10.0.0.99", subnetMask: "255.255.255.0")
        XCTAssertTrue(IPUtils.areSameRoutes(r1, r2))
    }

    func testAreSameRoutes_differentNetworks() {
        let r1 = NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.255.255.0")
        let r2 = NEIPv4Route(destinationAddress: "10.0.1.0", subnetMask: "255.255.255.0")
        XCTAssertFalse(IPUtils.areSameRoutes(r1, r2))
    }

    func testAreSameRoutes_differentMasks() {
        let r1 = NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.255.0.0")
        let r2 = NEIPv4Route(destinationAddress: "10.0.1.0", subnetMask: "255.255.0.0")
        // Both in 10.0.0.0/16
        XCTAssertTrue(IPUtils.areSameRoutes(r1, r2))
    }

    // MARK: - inV4Subnet

    func testInV4Subnet_addressInSubnet() {
        let dest = IPUtils.ipV4AddressStringToData("10.0.0.5")
        let network = IPUtils.ipV4AddressStringToData("10.0.0.0")
        let mask = IPUtils.ipV4AddressStringToData("255.255.255.0")
        XCTAssertTrue(IPUtils.inV4Subnet(dest, network: network, mask: mask))
    }

    func testInV4Subnet_addressOutsideSubnet() {
        let dest = IPUtils.ipV4AddressStringToData("10.0.1.5")
        let network = IPUtils.ipV4AddressStringToData("10.0.0.0")
        let mask = IPUtils.ipV4AddressStringToData("255.255.255.0")
        XCTAssertFalse(IPUtils.inV4Subnet(dest, network: network, mask: mask))
    }

    func testInV4Subnet_broadMask() {
        let dest = IPUtils.ipV4AddressStringToData("10.1.2.3")
        let network = IPUtils.ipV4AddressStringToData("10.0.0.0")
        let mask = IPUtils.ipV4AddressStringToData("255.0.0.0")
        XCTAssertTrue(IPUtils.inV4Subnet(dest, network: network, mask: mask))
    }

    func testInV4Subnet_hostMask() {
        // /32 mask - exact match only
        let dest = IPUtils.ipV4AddressStringToData("10.0.0.1")
        let network = IPUtils.ipV4AddressStringToData("10.0.0.1")
        let mask = IPUtils.ipV4AddressStringToData("255.255.255.255")
        XCTAssertTrue(IPUtils.inV4Subnet(dest, network: network, mask: mask))
    }

    func testInV4Subnet_hostMask_noMatch() {
        let dest = IPUtils.ipV4AddressStringToData("10.0.0.2")
        let network = IPUtils.ipV4AddressStringToData("10.0.0.1")
        let mask = IPUtils.ipV4AddressStringToData("255.255.255.255")
        XCTAssertFalse(IPUtils.inV4Subnet(dest, network: network, mask: mask))
    }

    func testInV4Subnet_zeroMask() {
        // /0 mask - everything matches
        let dest = IPUtils.ipV4AddressStringToData("192.168.1.1")
        let network = IPUtils.ipV4AddressStringToData("10.0.0.0")
        let mask = IPUtils.ipV4AddressStringToData("0.0.0.0")
        XCTAssertTrue(IPUtils.inV4Subnet(dest, network: network, mask: mask))
    }
}
