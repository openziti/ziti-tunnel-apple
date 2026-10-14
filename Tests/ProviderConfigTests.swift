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

    // MARK: - Value Coercion

    func testStringValue() {
        XCTAssertEqual(ProviderConfig.stringValue("4000"), "4000")
        XCTAssertEqual(ProviderConfig.stringValue(4000), "4000")
        XCTAssertEqual(ProviderConfig.stringValue(NSNumber(value: 4000.0)), "4000")
        XCTAssertNil(ProviderConfig.stringValue(true))
        XCTAssertNil(ProviderConfig.stringValue(["4000"]))
        XCTAssertNil(ProviderConfig.stringValue(nil))
    }

    func testIntValue() {
        XCTAssertEqual(ProviderConfig.intValue("4000"), 4000)
        XCTAssertEqual(ProviderConfig.intValue(4000), 4000)
        XCTAssertEqual(ProviderConfig.intValue(-1), -1)
        XCTAssertNil(ProviderConfig.intValue("abc"))
        XCTAssertNil(ProviderConfig.intValue(4000.5))
        XCTAssertNil(ProviderConfig.intValue(true))
        XCTAssertNil(ProviderConfig.intValue(nil))
    }

    func testBoolValue() {
        XCTAssertEqual(ProviderConfig.boolValue(true), true)
        XCTAssertEqual(ProviderConfig.boolValue(false), false)
        XCTAssertEqual(ProviderConfig.boolValue(1), true)
        XCTAssertEqual(ProviderConfig.boolValue(0), false)
        XCTAssertEqual(ProviderConfig.boolValue("YES"), true)
        XCTAssertEqual(ProviderConfig.boolValue("true"), true)
        XCTAssertEqual(ProviderConfig.boolValue("No"), false)
        XCTAssertEqual(ProviderConfig.boolValue("0"), false)
        XCTAssertNil(ProviderConfig.boolValue("maybe"))
        XCTAssertNil(ProviderConfig.boolValue(nil))
    }

    // MARK: - Typed Values

    func testValidate_mtuAsNumber_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.MTU_KEY] = 1500
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_mtuAsBool_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.MTU_KEY] = true
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidMtu)
    }

    func testValidate_mtuMissing_fails() {
        var conf = validBaseConfig()
        conf.removeValue(forKey: ProviderConfig.MTU_KEY)
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidMtu)
    }

    func testValidate_logRotateCountNotNumeric_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.LOG_ROTATE_COUNT_KEY] = "abc"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidLogRotateCount)
    }

    func testValidate_logRotateSizeNotNumeric_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.LOG_ROTATE_SIZEMB_KEY] = "abc"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidLogRotateSizeMB)
    }

    func testValidate_fallbackDnsEnabledAsString_requiresFallbackDns() {
        var conf = validBaseConfig()
        conf[ProviderConfig.FALLBACK_DNS_ENABLED_KEY] = "yes"
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidFallbackDns)
    }

    func testValidate_proxyManual_portAsNumber_succeeds() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = 3128
        XCTAssertNil(ProviderConfig().validateDictionaty(conf))
    }

    func testValidate_proxyManual_portAsNumberZero_fails() {
        var conf = validBaseConfig()
        conf[ProviderConfig.PROXY_MODE_KEY] = "manual"
        conf[ProviderConfig.PROXY_HOST_KEY] = "proxy.example.com"
        conf[ProviderConfig.PROXY_PORT_KEY] = 0
        XCTAssertEqual(ProviderConfig().validateDictionaty(conf), .invalidProxyPort)
    }

    func testParse_typedValues_fromPropertyList() throws {
        // Round-trip through a property list so values carry the same CF types a plist would produce
        let typed: ProviderConfigDict = [
            ProviderConfig.IP_KEY: "100.64.0.1",
            ProviderConfig.SUBNET_KEY: "255.192.0.0",
            ProviderConfig.DNS_KEY: "100.64.0.2",
            ProviderConfig.MTU_KEY: 1500,
            ProviderConfig.LOG_LEVEL_KEY: 4,
            ProviderConfig.LOG_TLSUV_KEY: true,
            ProviderConfig.FALLBACK_DNS_ENABLED_KEY: true,
            ProviderConfig.FALLBACK_DNS_KEY: "9.9.9.9",
            ProviderConfig.INTERCEPT_MATCHED_DNS_KEY: false,
            ProviderConfig.LOW_POWER_MODE_KEY: true,
            ProviderConfig.LOG_ROTATE_DAILY_KEY: false,
            ProviderConfig.LOG_ROTATE_COUNT_KEY: 7,
            ProviderConfig.LOG_ROTATE_SIZEMB_KEY: 20,
            ProviderConfig.PROXY_MODE_KEY: "manual",
            ProviderConfig.PROXY_HOST_KEY: "proxy.example.com",
            ProviderConfig.PROXY_PORT_KEY: 3128
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: typed, format: .xml, options: 0)
        let conf = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? ProviderConfigDict)

        let pc = ProviderConfig()
        XCTAssertNil(pc.parseDictionary(conf))
        XCTAssertEqual(pc.mtu, 1500)
        XCTAssertEqual(pc.logLevel, 4)
        XCTAssertTrue(pc.logTlsuv)
        XCTAssertTrue(pc.fallbackDnsEnabled)
        XCTAssertEqual(pc.fallbackDns, "9.9.9.9")
        XCTAssertFalse(pc.interceptMatchedDns)
        XCTAssertTrue(pc.lowPowerMode)
        XCTAssertFalse(pc.logRotateDaily)
        XCTAssertEqual(pc.logRotateCount, 7)
        XCTAssertEqual(pc.logRotateSizeMB, 20)
        XCTAssertEqual(pc.proxyPort, "3128")
    }

    func testParse_logLevelInvalid_defaultsToInfo() {
        var conf = validBaseConfig()
        conf[ProviderConfig.LOG_LEVEL_KEY] = "abc"
        let pc = ProviderConfig()
        XCTAssertNil(pc.parseDictionary(conf))
        XCTAssertEqual(pc.logLevel, 3)
    }

    // MARK: - Upgrade Compatibility

    func testCreateDictionary_storesNumericFieldsAsStrings() {
        // Stored format must stay readable by older app versions
        let dict = ProviderConfig().createDictionary()
        for key in [ProviderConfig.MTU_KEY, ProviderConfig.LOG_LEVEL_KEY,
                    ProviderConfig.LOG_ROTATE_COUNT_KEY, ProviderConfig.LOG_ROTATE_SIZEMB_KEY,
                    ProviderConfig.PROXY_PORT_KEY] {
            XCTAssertTrue(dict[key] is String, "\(key) should be stored as a String")
        }
    }

    func testRoundTrip_allFields() {
        let original = ProviderConfig()
        original.ipAddress = "100.64.0.9"
        original.subnetMask = "255.255.0.0"
        original.mtu = 1400
        original.dnsAddresses = ["100.64.0.3", "100.64.0.4"]
        original.fallbackDnsEnabled = true
        original.fallbackDns = "8.8.8.8"
        original.interceptMatchedDns = false
        original.lowPowerMode = true
        original.logLevel = 5
        original.logTlsuv = true
        original.logRotateDaily = false
        original.logRotateCount = 9
        original.logRotateSizeMB = 11

        let restored = ProviderConfig()
        XCTAssertNil(restored.parseDictionary(original.createDictionary()))
        XCTAssertEqual(restored.debugDescription.split(separator: "\n").dropFirst(),
                       original.debugDescription.split(separator: "\n").dropFirst())
    }
}
