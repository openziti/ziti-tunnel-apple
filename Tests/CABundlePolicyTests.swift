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

final class CABundlePolicyTests: XCTestCase {

    private func cert(_ pem:String) -> SecCertificate {
        return CABundlePolicy.certificates(pem)!.first!
    }

    private func policy(_ pems:String...) -> CABundlePolicy {
        return CABundlePolicy(pems.map { CABundlePolicy.fingerprint(cert($0)) })
    }

    private func bundle(_ pems:String...) -> String {
        return pems.joined(separator: "\n")
    }

    // MARK: - Fingerprints

    func testFingerprintFormats() {
        let hex = CABundlePolicy.fingerprint(cert(CAFixtures.rootA))
        let display = CABundlePolicy.displayFingerprint(cert(CAFixtures.rootA))
        XCTAssertEqual(display, "15:71:F3:C0:A1:A7:AB:7F:1C:C0:41:A2:BE:4C:20:66:32:4F:28:A6:6D:1E:03:02:B5:89:A8:53:A1:99:BC:40")
        XCTAssertEqual(CABundlePolicy([display]).fingerprints, [hex])
        XCTAssertEqual(CABundlePolicy([hex.uppercased(), " \(hex)\n"]).fingerprints, [hex])
    }

    func testInvalidFingerprintsSkipped() {
        let hex = CABundlePolicy.fingerprint(cert(CAFixtures.rootA))
        let policy = CABundlePolicy(["", "abc", String(hex.dropLast()), String(hex.dropLast()) + "g", hex])
        XCTAssertEqual(policy.fingerprints, [hex])
    }

    func testNoFingerprintsAllowsNothing() {
        XCTAssertNotEqual(CABundlePolicy([]).check(CAFixtures.rootA), .allowed)
        XCTAssertNotEqual(CABundlePolicy(["abc"]).check(CAFixtures.rootA), .allowed)
    }

    // MARK: - Bundles

    func testAllowedRoot() {
        XCTAssertEqual(policy(CAFixtures.rootA).check(CAFixtures.rootA), .allowed)
    }

    func testChainsToAllowedRoot() {
        let p = policy(CAFixtures.rootA)
        XCTAssertEqual(p.check(bundle(CAFixtures.interA, CAFixtures.rootA)), .allowed)
        XCTAssertEqual(p.check(bundle(CAFixtures.interA2, CAFixtures.interA, CAFixtures.rootA)), .allowed)
        XCTAssertEqual(p.check(bundle(CAFixtures.rootA, CAFixtures.interA2, CAFixtures.interA)), .allowed)
    }

    func testAllowedIntermediateOnly() {
        // partial chains: an allowed intermediate is enough on its own
        XCTAssertEqual(policy(CAFixtures.interA).check(CAFixtures.interA), .allowed)
        XCTAssertEqual(policy(CAFixtures.interA).check(bundle(CAFixtures.interA2, CAFixtures.interA)), .allowed)
    }

    func testRootAboveAllowedIntermediateBlocked() {
        // the root is an anchor too, and it trusts more than the intermediate does
        XCTAssertNotEqual(policy(CAFixtures.interA).check(bundle(CAFixtures.interA, CAFixtures.rootA)), .allowed)
    }

    func testOtherNetworkBlocked() {
        let rootB = CABundlePolicy.displayFingerprint(cert(CAFixtures.rootB))
        XCTAssertEqual(policy(CAFixtures.rootA).check(bundle(CAFixtures.rootA, CAFixtures.rootB)), .blocked("CA \(rootB) isn't allowed"))
        XCTAssertNotEqual(policy(CAFixtures.rootA).check(CAFixtures.rootB), .allowed)
        XCTAssertEqual(policy(CAFixtures.rootA, CAFixtures.rootB).check(bundle(CAFixtures.rootA, CAFixtures.rootB)), .allowed)
    }

    func testImpostorIssuerBlocked() {
        XCTAssertNotEqual(policy(CAFixtures.rootA).check(bundle(CAFixtures.rootA, CAFixtures.impostorInter)), .allowed)
    }

    func testValidityDatesDontMatter() {
        XCTAssertEqual(policy(CAFixtures.rootA).check(bundle(CAFixtures.rootA, CAFixtures.expiredA, CAFixtures.futureA)), .allowed)
        XCTAssertEqual(policy(CAFixtures.expiredA).check(CAFixtures.expiredA), .allowed)
    }

    func testEmptyOrUnreadableBundleBlocked() {
        let p = policy(CAFixtures.rootA)
        XCTAssertEqual(p.check(nil), .blocked("no CA bundle"))
        XCTAssertEqual(p.check(""), .blocked("no CA bundle"))
        XCTAssertEqual(p.check("pem:"), .blocked("no CA bundle"))
        XCTAssertEqual(p.check(" \n\t"), .blocked("no CA bundle"))
        XCTAssertEqual(p.check("not a bundle"), .blocked("CA bundle can't be read"))
        XCTAssertEqual(p.check("-----BEGIN CERTIFICATE-----\n!!!\n-----END CERTIFICATE-----"), .blocked("CA bundle can't be read"))
        XCTAssertEqual(p.check(bundle(CAFixtures.rootA, "-----BEGIN CERTIFICATE-----\nMIIB")), .blocked("CA bundle can't be read"))
    }

    func testPemPrefix() {
        XCTAssertEqual(policy(CAFixtures.rootA).check("pem:" + CAFixtures.rootA), .allowed)
    }

    func testWhitespaceAroundBlocks() {
        let crlf = bundle(CAFixtures.interA, CAFixtures.rootA).replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(policy(CAFixtures.rootA).check("\n  " + crlf + "\r\n\n"), .allowed)
    }

    // The SDK reads more than CERTIFICATE blocks, so anything else must not get past the check with an allowed cert
    func testOtherTextBlocked() {
        let p = policy(CAFixtures.rootA)
        let legacy = CAFixtures.rootB.replacingOccurrences(of: "CERTIFICATE-----", with: "X509 CERTIFICATE-----")
        let trusted = CAFixtures.rootB.replacingOccurrences(of: "CERTIFICATE-----", with: "TRUSTED CERTIFICATE-----")
        for (name, ca) in [
            ("legacy label", bundle(CAFixtures.rootA, legacy)),
            ("trusted label", bundle(CAFixtures.rootA, trusted)),
            ("file URL", "file:///nonexistent/" + CAFixtures.rootA),
            ("file reference", "file:/nonexistent/" + CAFixtures.rootA),
            ("path", "/nonexistent/dir\n" + CAFixtures.rootA),
            ("leading text", "subject=CN=rootA\n" + CAFixtures.rootA),
            ("trailing text", CAFixtures.rootA + "\ntrailer"),
            ("text between", bundle(CAFixtures.interA, "comment", CAFixtures.rootA)),
            ("pem prefix twice", "pem:pem:" + CAFixtures.rootA),
        ] {
            XCTAssertEqual(p.check(ca), .blocked("CA bundle can't be read"), name)
        }
    }

    func testPemRoundTrip() {
        let certs = CABundlePolicy.certificates("pem:" + bundle(CAFixtures.interA, CAFixtures.rootA))!
        let pem = CABundlePolicy.pem(certs)
        XCTAssertTrue(pem.hasPrefix("-----BEGIN CERTIFICATE-----\n"))
        XCTAssertTrue(pem.hasSuffix("-----END CERTIFICATE-----\n"))
        XCTAssertFalse(pem.contains("pem:"))
        XCTAssertTrue(pem.components(separatedBy: "\n").allSatisfy { $0.count <= 64 })
        XCTAssertEqual(CABundlePolicy.certificates(pem)!.map(CABundlePolicy.fingerprint), certs.map(CABundlePolicy.fingerprint))
        XCTAssertEqual(policy(CAFixtures.rootA).check(pem), .allowed)
        XCTAssertEqual(CABundlePolicy.pem([]), "")
    }

    // MARK: - Tunnel decisions

    func testLoadGivesTheSDKTheCheckedCertificates() {
        let p = policy(CAFixtures.rootA)
        let ca = "pem:\r\n" + bundle(CAFixtures.interA, CAFixtures.rootA).replacingOccurrences(of: "\n", with: "\r\n")
        let expected = CABundlePolicy.pem(CABundlePolicy.certificates(ca)!)
        XCTAssertEqual(p.load(ca), .load(expected))
        XCTAssertNotEqual(expected, ca)
        XCTAssertEqual(p.load(CABundlePolicy.pem(CABundlePolicy.certificates(CAFixtures.rootA)!)),
                       .load(CABundlePolicy.pem(CABundlePolicy.certificates(CAFixtures.rootA)!)))
    }

    func testLoadBlocksWhatCheckBlocks() {
        let p = policy(CAFixtures.rootA)
        XCTAssertEqual(p.load(nil), .blocked("no CA bundle"))
        XCTAssertEqual(p.load("file:///nonexistent/" + CAFixtures.rootA), .blocked("CA bundle can't be read"))
        guard case .blocked(let reason) = p.load(bundle(CAFixtures.rootA, CAFixtures.rootB)) else {
            return XCTFail("outside root loaded")
        }
        XCTAssertEqual(reason, "CA \(CABundlePolicy.displayFingerprint(cert(CAFixtures.rootB))) isn't allowed")
    }

    func testStopReasonForRefreshedBundle() {
        let p = policy(CAFixtures.rootA)
        XCTAssertNil(p.stopReason(refreshed: ""), "an event without a bundle keeps the current one")
        XCTAssertNil(p.stopReason(refreshed: bundle(CAFixtures.interA, CAFixtures.rootA)))
        XCTAssertEqual(p.stopReason(refreshed: CAFixtures.rootB),
                       "CA \(CABundlePolicy.displayFingerprint(cert(CAFixtures.rootB))) isn't allowed")
        XCTAssertEqual(p.stopReason(refreshed: "junk"), "CA bundle can't be read")
    }

    func testPolicyStops() {
        var stops = PolicyStops()
        XCTAssertTrue(stops.shouldRun("a", enabled: true))
        XCTAssertFalse(stops.shouldRun("a", enabled: false))
        XCTAssertEqual(stops.setEnabled("a", true), .proceed)
        XCTAssertEqual(stops.setEnabled("a", false), .proceed)

        stops.stop("a")
        XCTAssertFalse(stops.shouldRun("a", enabled: true), "sleep and wake leave a stopped identity alone")
        XCTAssertEqual(stops.setEnabled("a", true), .refuse)
        XCTAssertEqual(stops.setEnabled("a", false), .alreadyStopped)
        XCTAssertTrue(stops.shouldRun("b", enabled: true))
        XCTAssertEqual(stops.setEnabled("b", true), .proceed)
    }

    // MARK: - Identities

    func testBlocksEnrolledIdentitiesOnly() {
        let p = policy(CAFixtures.rootA)
        let zid = ZitiIdentity()
        zid.czid = CZiti.ZitiIdentity(id: "id", ztAPIs: ["https://ctrl"], ca: CAFixtures.rootB)
        XCTAssertFalse(p.blocks(zid), "pending: checked when it enrolls")
        zid.enrolled = true
        XCTAssertTrue(p.blocks(zid))
        zid.czid?.ca = CAFixtures.rootA
        XCTAssertFalse(p.blocks(zid))
        zid.czid?.ca = nil
        XCTAssertTrue(p.blocks(zid))
    }

    // MARK: - Validity

    func testValidity() {
        let utc = { (y:Int, m:Int, d:Int) -> Date in
            var c = DateComponents(year: y, month: m, day: d)
            c.timeZone = TimeZone(identifier: "UTC")
            return Calendar(identifier: .gregorian).date(from: c)!
        }
        let expired = CABundlePolicy.validity(cert(CAFixtures.expiredA))
        XCTAssertEqual(expired?.0, utc(2020, 1, 1))
        XCTAssertEqual(expired?.1, utc(2021, 1, 1))

        // GeneralizedTime from 2050 on
        let root = CABundlePolicy.validity(cert(CAFixtures.rootA))
        XCTAssertEqual(root?.0, utc(2019, 1, 1))
        XCTAssertEqual(root?.1, utc(2099, 12, 31))
        XCTAssertEqual(CABundlePolicy.validity(cert(CAFixtures.futureA))?.0, utc(2090, 1, 1))
    }
}

/// EC P-256 CAs made with OpenSSL for these tests
enum CAFixtures {
    /// Network A root (self-signed), 2019-2099
    static let rootA = """
-----BEGIN CERTIFICATE-----
MIIBpzCCAUygAwIBAgIUKcpkHr/e/V619ttEPw+nBLnUypkwCgYIKoZIzj0EAwIw
MDESMBAGA1UECgwJRXhhbXBsZSBBMRowGAYDVQQDDBFFeGFtcGxlIEEgUm9vdCBD
QTAgFw0xOTAxMDEwMDAwMDBaGA8yMDk5MTIzMTAwMDAwMFowMDESMBAGA1UECgwJ
RXhhbXBsZSBBMRowGAYDVQQDDBFFeGFtcGxlIEEgUm9vdCBDQTBZMBMGByqGSM49
AgEGCCqGSM49AwEHA0IABAWI8dTHN0qJP4+WGkAIrqdwjgRvymEOC2JlXepvWQfk
2k8xSHuxXbuHpNb4HsUUsms+SXv2HO+sQjNWYyCXEqejQjBAMA8GA1UdEwEB/wQF
MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBRWh+ymuPZUT/m+jUJutdA7
PhhFazAKBggqhkjOPQQDAgNJADBGAiEA5qoyk8GEc3RD6y6ahQw59wyRTKKEqwj4
SwRO/kgG/pACIQCQVbyPT5IjHISUnByK03FubpntOg+cyL0lVqaXS34L1A==
-----END CERTIFICATE-----
"""

    /// Network A intermediate, issued by rootA, 2019-2089
    static let interA = """
-----BEGIN CERTIFICATE-----
MIIBzzCCAXWgAwIBAgIUL/9GJlhuIYUb1GHvFzMuWAhdwpcwCgYIKoZIzj0EAwIw
MDESMBAGA1UECgwJRXhhbXBsZSBBMRowGAYDVQQDDBFFeGFtcGxlIEEgUm9vdCBD
QTAgFw0xOTA2MDEwMDAwMDBaGA8yMDg5MDEwMTAwMDAwMFowODESMBAGA1UECgwJ
RXhhbXBsZSBBMSIwIAYDVQQDDBlFeGFtcGxlIEEgSW50ZXJtZWRpYXRlIENBMFkw
EwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEW3YGzRvk/ip2T75Y5zAgvyc0Q8E4Pa+L
82tFqAUVKJQjmeyoMtLX/CcU/z4dcpYnMaCIQTEi0Zt0AAnBnoGv66NjMGEwDwYD
VR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFAZkCfXrdFr5
K7U5c9Yy6dUeaQ9xMB8GA1UdIwQYMBaAFFaH7Ka49lRP+b6NQm610Ds+GEVrMAoG
CCqGSM49BAMCA0gAMEUCIQDyfEZxl+a6X8O3PLNrcQqjh9pa8VTapl/fRK4ykmkw
RwIgAv/1glZcP1cfx45HVoUssqXXkQVmIXiJ4Ml0nfDuTag=
-----END CERTIFICATE-----
"""

    /// Network A second-level intermediate, issued by interA, 2020-2079
    static let interA2 = """
-----BEGIN CERTIFICATE-----
MIIB0TCCAXigAwIBAgIULFy0ytpsq6kpSk6CHeorTtqFgVUwCgYIKoZIzj0EAwIw
ODESMBAGA1UECgwJRXhhbXBsZSBBMSIwIAYDVQQDDBlFeGFtcGxlIEEgSW50ZXJt
ZWRpYXRlIENBMCAXDTIwMDEwMTAwMDAwMFoYDzIwNzkwMTAxMDAwMDAwWjAzMRIw
EAYDVQQKDAlFeGFtcGxlIEExHTAbBgNVBAMMFEV4YW1wbGUgQSBTaWduaW5nIENB
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdhmnEW8KIKNCIAIHFAJLIg0F6TE2
hSwFuo9lT+XBSw/B4OtU5ugwcWzcmD7dE25WDb0kkATMuPm4I9Yg8Qo4+qNjMGEw
DwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFNVTxORZ
qlbbW9wi7ISPwF3E2PAnMB8GA1UdIwQYMBaAFAZkCfXrdFr5K7U5c9Yy6dUeaQ9x
MAoGCCqGSM49BAMCA0cAMEQCIAs5Cha1Zo6cb/16VC6V+Q5WZJBXRBZCgQhhIA6t
hyBWAiBgJA/HsH+RR86+mHbpf3mW2MC5spXLJLXFU9vfgPH8sw==
-----END CERTIFICATE-----
"""

    /// Network A intermediate, issued by rootA, expired (2020-2021)
    static let expiredA = """
-----BEGIN CERTIFICATE-----
MIIB0TCCAXegAwIBAgIUeF3gJXPc7KwhKrgbrDpy3gmXRFcwCgYIKoZIzj0EAwIw
MDESMBAGA1UECgwJRXhhbXBsZSBBMRowGAYDVQQDDBFFeGFtcGxlIEEgUm9vdCBD
QTAeFw0yMDAxMDEwMDAwMDBaFw0yMTAxMDEwMDAwMDBaMDwxEjAQBgNVBAoMCUV4
YW1wbGUgQTEmMCQGA1UEAwwdRXhhbXBsZSBBIE9sZCBJbnRlcm1lZGlhdGUgQ0Ew
WTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASi1wEUJkRSvL3K98TysfslqcFrbTk2
75D4zrZsxUHg21KoAHI9rrj0GdCHwF0Uh5eW7CF1NxhO2RuVKY5KHPU5o2MwYTAP
BgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQU5XiZ9kOW
jKAqBfgxcDlnQ1XIFGowHwYDVR0jBBgwFoAUVofsprj2VE/5vo1CbrXQOz4YRWsw
CgYIKoZIzj0EAwIDSAAwRQIgIpCTxzsbe+VJlfaSE2QRfyuaLty26o80tfbIb4aU
+LMCIQDNKvaJnWxKgR6G6BcCpEoIVSCjiHbWCMU8G9Y24YDVFQ==
-----END CERTIFICATE-----
"""

    /// Network A intermediate, issued by rootA, not valid yet (2090-2095)
    static let futureA = """
-----BEGIN CERTIFICATE-----
MIIB1zCCAXygAwIBAgIUKbQcHclY/drg/QojlczCGwqp4EQwCgYIKoZIzj0EAwIw
MDESMBAGA1UECgwJRXhhbXBsZSBBMRowGAYDVQQDDBFFeGFtcGxlIEEgUm9vdCBD
QTAiGA8yMDkwMDEwMTAwMDAwMFoYDzIwOTUwMTAxMDAwMDAwWjA9MRIwEAYDVQQK
DAlFeGFtcGxlIEExJzAlBgNVBAMMHkV4YW1wbGUgQSBOZXh0IEludGVybWVkaWF0
ZSBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABK5Xihhco3VmDgtkaOY+e9+L
2YUW/MYcBPasVjP2wu1ZygDN/egNize0695qSBOs9E9lMgYhjoRuxJdoQAok7Eyj
YzBhMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBR+
MSrE3GmMBiWe4qUOrJieuB7euDAfBgNVHSMEGDAWgBRWh+ymuPZUT/m+jUJutdA7
PhhFazAKBggqhkjOPQQDAgNJADBGAiEAgRv9zXTD6q399F5a6nHvDYavoSK9186v
9cGkDeO3ub4CIQC3Gv/JcC4DM5DiTcY4+/LdMnDJPOENfE8XTKhvk6mhYg==
-----END CERTIFICATE-----
"""

    /// Network B root (self-signed), 2019-2099
    static let rootB = """
-----BEGIN CERTIFICATE-----
MIIBpjCCAUygAwIBAgIUJc5rhRAFzyvTvmRsl8Ix1Kurna0wCgYIKoZIzj0EAwIw
MDESMBAGA1UECgwJRXhhbXBsZSBCMRowGAYDVQQDDBFFeGFtcGxlIEIgUm9vdCBD
QTAgFw0xOTAxMDEwMDAwMDBaGA8yMDk5MTIzMTAwMDAwMFowMDESMBAGA1UECgwJ
RXhhbXBsZSBCMRowGAYDVQQDDBFFeGFtcGxlIEIgUm9vdCBDQTBZMBMGByqGSM49
AgEGCCqGSM49AwEHA0IABBJ2R+yjp5vUtqsPMDUjlp3tjE62ck4QBTG0cn42Gr22
/CdpnEzahvblEkH6c9jAXST6q2bX3Nq/GBDnR0qO6pCjQjBAMA8GA1UdEwEB/wQF
MAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTV4EY4t4pKJO14IWS+oF1H
dXmyrTAKBggqhkjOPQQDAgNIADBFAiBFIop0AfwcWHKLnKhKVSPnqluFUDyNgO/A
9riFovLPLAIhAMM88M3Y1xGWoCaZ63X+nCfQZif6Q14E6CXV+Pehh1Nv
-----END CERTIFICATE-----
"""

    /// Claims rootA as its issuer (same name) but is signed by another key
    static let impostorInter = """
-----BEGIN CERTIFICATE-----
MIIB0DCCAXWgAwIBAgIUIuDiOlyw66Ha5eYmf3I77nHuEWQwCgYIKoZIzj0EAwIw
MDESMBAGA1UECgwJRXhhbXBsZSBBMRowGAYDVQQDDBFFeGFtcGxlIEEgUm9vdCBD
QTAgFw0xOTA2MDEwMDAwMDBaGA8yMDg5MDEwMTAwMDAwMFowODESMBAGA1UECgwJ
RXhhbXBsZSBBMSIwIAYDVQQDDBlFeGFtcGxlIEEgSW50ZXJtZWRpYXRlIENBMFkw
EwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEb0Paol9K1Dk51b9Bo+OKhKoWlZNFZmjS
/u99RX3RzFDDjRapsyanoeV/PzEOfW60RvbJ+mynJQ3xvCSLJ8UZC6NjMGEwDwYD
VR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFDl1MC4bFNTq
fge2Ot1MmQh9qkzVMB8GA1UdIwQYMBaAFIz1B9Nzre9sbzCrT69eNGval2XiMAoG
CCqGSM49BAMCA0kAMEYCIQCjxn6R9YzYblLCxxB1TUW9eM3qFnwVXcoS2ELzxt/r
xAIhAIaIU/zsEJXrcuuJpzEBOPDAGmopY0pLKM8vw8epJcO9
-----END CERTIFICATE-----
"""
}
