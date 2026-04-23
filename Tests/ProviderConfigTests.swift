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

class ProviderConfigTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a valid base config dict with required fields populated
    func validBaseConfig() -> ProviderConfigDict {
        return [
            ProviderConfig.IP_KEY: "100.64.0.1",
            ProviderConfig.SUBNET_KEY: "255.192.0.0",
            ProviderConfig.MTU_KEY: "4000",
            ProviderConfig.DNS_KEY: "100.64.0.2"
        ]
    }

    // MARK: - Proxy Validation

    func testValidate_proxyNone_noHostPort_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "none"
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_proxyNone_missingKey_succeeds() {
        let conf = validBaseConfig()
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_proxyManual_validHostPort_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "3128"
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_proxyManual_emptyHost_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = ""
        conf[ProviderConfig.PROXY_PORT_KEY] = "3128"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyHost)
    }

    func testValidate_proxyManual_missingHost_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_PORT_KEY] = "3128"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyHost)
    }

    func testValidate_proxyManual_emptyPort_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = ""
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyPort)
    }

    func testValidate_proxyManual_missingPort_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyPort)
    }

    func testValidate_proxyManual_portZero_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "0"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyPort)
    }

    func testValidate_proxyManual_portTooHigh_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "65536"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyPort)
    }

    func testValidate_proxyManual_portNotNumeric_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "abc"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyPort)
    }

    func testValidate_proxyManual_port1_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "1"
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_proxyManual_port65535_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "65535"
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_proxySystem_noHostPort_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "system"
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    // MARK: - Proxy Parsing

    func testParse_proxyManual_setsAllFields() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = "8080"

        let pc = ProviderConfig()
        XCTAssertNil(pc.parseDictionary(conf))
        XCTAssertEqual(pc.proxyMode, "manual")
        XCTAssertEqual(pc.proxyHost, "proxy.example.com")
        XCTAssertEqual(pc.proxyPort, "8080")
    }

    func testParse_proxyMissing_usesDefaults() {
        let conf = validBaseConfig()
        let pc = ProviderConfig()
        XCTAssertNil(pc.parseDictionary(conf))
        XCTAssertEqual(pc.proxyMode, "none")
        XCTAssertEqual(pc.proxyHost, "")
        XCTAssertEqual(pc.proxyPort, "")
    }

    func testParse_proxyHost_trimmed() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "  proxy.example.com  "
        conf[ProviderConfig.PROXY_PORT_KEY] = "3128"

        let pc = ProviderConfig()
        XCTAssertNil(pc.parseDictionary(conf))
        XCTAssertEqual(pc.proxyHost, "proxy.example.com")
    }

    // MARK: - Proxy Round-Trip

    func testCreateDictionary_includesProxyKeys() {
        let pc = ProviderConfig()
        pc.proxyMode = "manual"
        pc.proxyHost = "proxy.example.com"
        pc.proxyPort = "3128"

        let dict = pc.createDictionary()
        XCTAssertEqual(dict[ProviderConfig.PROXY_MODE_KEY] as? String, "manual")
        XCTAssertEqual(dict[ProviderConfig.PROXY_HOST_KEY] as? String, "proxy.example.com")
        XCTAssertEqual(dict[ProviderConfig.PROXY_PORT_KEY] as? String, "3128")
    }

    func testRoundTrip_proxyConfig() {
        let original = ProviderConfig()
        original.proxyMode = "manual"
        original.proxyHost = "squid.local"
        original.proxyPort = "8888"

        let dict = original.createDictionary()
        let restored = ProviderConfig()
        XCTAssertNil(restored.parseDictionary(dict))
        XCTAssertEqual(restored.proxyMode, original.proxyMode)
        XCTAssertEqual(restored.proxyHost, original.proxyHost)
        XCTAssertEqual(restored.proxyPort, original.proxyPort)
    }
}
