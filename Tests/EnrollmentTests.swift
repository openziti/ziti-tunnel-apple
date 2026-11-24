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

private class FakeSDK : EnrollmentSDK {
    var providers:[Enrollment.Provider]?
    var result:(CZiti.ZitiIdentity?, Enrollment.Failure?) = (CZiti.ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl"]), nil)
    var enrollToResult:(CZiti.ZitiIdentity?, Enrollment.Failure?)?
    var mfaCodeError:String??
    var calls:[String] = []

    func queryProviders(_ source:Enrollment.Source, _ cb:@escaping ([Enrollment.Provider]?) -> Void) {
        calls.append("query \(source)")
        cb(providers)
    }

    func enroll(_ source:Enrollment.Source, _ cb:@escaping Callback) {
        calls.append("enroll \(source)")
        cb(result.0, result.1)
        cb(result.0, result.1)
    }

    func enroll(_ source:Enrollment.Source, to enrollTo:ZitiIdentity.EnrollTo, provider:String,
                onAuth:@escaping (String) -> Void, onMfaSetup:@escaping MfaSetupCallback, onMfaCode:@escaping MfaCodeCallback,
                _ cb:@escaping Callback) {
        calls.append("enroll \(source) to \(enrollTo) with \(provider)")
        let result = enrollToResult ?? self.result
        guard let mfaCodeError = mfaCodeError else {
            cb(result.0, result.1)
            return
        }
        onMfaCode(mfaCodeError) { code in
            self.calls.append("mfa code \(code ?? "nil")")
            cb(result.0, result.1)
        }
    }

    func discard(_ czid:CZiti.ZitiIdentity) {
        calls.append("discard \(czid.id)")
    }
}

private class FakeUI : EnrollmentUI {
    var enrollTo:ZitiIdentity.EnrollTo?
    var provider:String?
    var confirm = false
    var mfaCode:String?
    var calls:[String] = []

    func chooseProvider(_ zid:ZitiIdentity, _ names:[String], _ completion:@escaping (String?) -> Void) {
        calls.append("chooseProvider \(names)")
        completion(provider)
    }
    func chooseEnrollTo(_ zid:ZitiIdentity, _ completion:@escaping (ZitiIdentity.EnrollTo?) -> Void) {
        calls.append("chooseEnrollTo")
        completion(enrollTo)
    }
    func confirmBasicEnroll(_ info:(title:String, detail:String, action:String), _ completion:@escaping (Bool) -> Void) {
        calls.append("confirm \(info.title)")
        completion(confirm)
    }
    func openAuthURL(_ url:URL, _ completion:@escaping (Bool) -> Void) {
        calls.append("open \(url)")
        completion(true)
    }
    func authFinished() {
        calls.append("authFinished")
    }
    func mfaSetup(_ zid:ZitiIdentity, _ provisioningUrl:String, _ error:String?, _ submit:@escaping (String?) -> Void) {
        calls.append("mfaSetup")
        submit(mfaCode)
    }
    func mfaCode(_ zid:ZitiIdentity, _ error:String?, _ submit:@escaping (String?) -> Void) {
        calls.append("mfaCode \(error ?? "nil")")
        submit(mfaCode)
    }
    func showError(_ msg:String) {
        calls.append("error \(msg)")
    }
}

final class EnrollmentTests: XCTestCase {
    private let sdk = FakeSDK()
    private let ui = FakeUI()
    private let noJwt = "/nonexistent/id.jwt"
    private let both = [Enrollment.Provider(name: "both", canCert: true, canToken: true)]

    /// `currentPolicy`, when given, is what enrollment reads each time it asks; otherwise `policy` throughout
    private func run(_ zid:ZitiIdentity, jwtFile:String? = nil, hint:Enrollment.Hint = Enrollment.Hint(),
                     policy:CABundlePolicy? = nil, currentPolicy:(() -> Enrollment.Policy)? = nil) -> Enrollment.Result {
        let done = expectation(description: "enrollment completes")
        var result:Enrollment.Result?
        let fixed = TunnelMgr.enrollmentPolicy(loaded: true, policy)
        Enrollment(zid, ui: ui, sdk: sdk, hint: hint, policy: currentPolicy ?? { fixed }).start(jwtFile: jwtFile ?? noJwt) { r in
            XCTAssertNil(result, "completed more than once")
            result = r
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        // let any repeated SDK callback reach the main queue
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return result!
    }

    private func describe(_ result:Enrollment.Result) -> String {
        switch result {
        case .enrolled(let zidResp, let enrollTo): return "enrolled \(zidResp.id) \(enrollTo)"
        case .failed(let msg): return "failed \(msg)"
        case .cancelled: return "cancelled"
        // a refusal for the network keeps the short name the expectations use; any other says why
        case .refused(let msg): return msg == CABundlePolicy.notAllowedMessage ? "refused" : "refused \(msg)"
        }
    }

    // MARK: - Decisions

    func testSource() {
        XCTAssertEqual(Enrollment.source(jwtFile: "a.jwt", method: .ott, controllerURL: "https://c"), .ott("a.jwt"))
        XCTAssertEqual(Enrollment.source(jwtFile: "a.jwt", method: .url, controllerURL: "https://c"), .jwt("a.jwt"))
        XCTAssertEqual(Enrollment.source(jwtFile: "a.jwt", method: .unrecognized, controllerURL: nil), .jwt("a.jwt"))
        XCTAssertEqual(Enrollment.source(jwtFile: nil, method: .ott, controllerURL: "https://c"), .controller("https://c"))
        XCTAssertNil(Enrollment.source(jwtFile: nil, method: .ott, controllerURL: nil))
    }

    func testChoices() {
        XCTAssertNil(Enrollment.choices(nil))
        XCTAssertNil(Enrollment.choices([]))
        XCTAssertNil(Enrollment.choices([Enrollment.Provider(name: "basic", canCert: false, canToken: false)]))

        let providers = [Enrollment.Provider(name: "a", canCert: false, canToken: false),
                         Enrollment.Provider(name: "b", canCert: false, canToken: true)]
        XCTAssertEqual(Enrollment.choices(providers), providers)
    }

    // MARK: - Flow

    func testOttEnrollsDirectly() throws {
        let jwtFile = NSTemporaryDirectory() + UUID().uuidString + ".jwt"
        try "jwt".write(toFile: jwtFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: jwtFile) }

        let result = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "ott"]), jwtFile: jwtFile)
        XCTAssertEqual(describe(result), "enrolled real-id none")
        XCTAssertEqual(sdk.calls, ["enroll ott(\"\(jwtFile)\")"])
        XCTAssertEqual(ui.calls, [])
    }

    func testNetworkJwtQueriesProviders() throws {
        let jwtFile = NSTemporaryDirectory() + UUID().uuidString + ".jwt"
        try "jwt".write(toFile: jwtFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: jwtFile) }

        _ = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"]), jwtFile: jwtFile)
        XCTAssertEqual(sdk.calls, ["query jwt(\"\(jwtFile)\")", "enroll jwt(\"\(jwtFile)\")"])
    }

    func testNothingToEnrollWith() {
        let zid = makeIdentity()
        zid.czid = nil
        XCTAssertEqual(describe(run(zid)), "failed No JWT file or controller URL available")
        XCTAssertEqual(sdk.calls, [])
    }

    func testQueryFailureFallsBackToBasic() {
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id none")
        XCTAssertEqual(sdk.calls, ["query controller(\"https://ctrl.example.com\")", "enroll controller(\"https://ctrl.example.com\")"])
    }

    func testNoEnrollToProvidersUsesBasicWithoutAsking() {
        sdk.providers = [Enrollment.Provider(name: "a", canCert: false, canToken: false),
                         Enrollment.Provider(name: "b", canCert: false, canToken: false)]
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id none")
        XCTAssertEqual(ui.calls, [])
    }

    func testSingleProviderSkipsDialogs() {
        sdk.providers = [Enrollment.Provider(name: "okta", canCert: true, canToken: false)]
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id cert")
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\") to cert with okta")
        XCTAssertEqual(ui.calls, ["authFinished"])
    }

    func testChooseProviderThenType() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        ui.provider = "both"
        ui.enrollTo = .cert
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id cert")
        XCTAssertEqual(ui.calls, ["chooseProvider [\"both\", \"token2\"]", "chooseEnrollTo", "authFinished"])
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\") to cert with both")
    }

    func testChosenProviderWithOneTypeSkipsTypeDialog() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        ui.provider = "token2"
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id token")
        XCTAssertEqual(ui.calls, ["chooseProvider [\"both\", \"token2\"]", "authFinished"])
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\") to token with token2")
    }

    func testChosenProviderWithoutEnrollToUsesBasic() {
        sdk.providers = both + [Enrollment.Provider(name: "legacy", canCert: false, canToken: false)]
        ui.provider = "legacy"
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id none")
        XCTAssertEqual(ui.calls, ["chooseProvider [\"both\", \"legacy\"]"])
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\")")
    }

    func testHintsSkipDialogs() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        XCTAssertEqual(describe(run(makeIdentity(), hint: Enrollment.Hint(provider: "both", enrollTo: .cert))), "enrolled real-id cert")
        XCTAssertEqual(ui.calls, ["authFinished"])
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\") to cert with both")
    }

    func testUnknownProviderHintAsks() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        ui.provider = "token2"
        XCTAssertEqual(describe(run(makeIdentity(), hint: Enrollment.Hint(provider: "gone", enrollTo: nil))), "enrolled real-id token")
        XCTAssertEqual(ui.calls, ["chooseProvider [\"both\", \"token2\"]", "authFinished"])
    }

    func testTypeHintIgnoredWhenProviderOffersOneType() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        XCTAssertEqual(describe(run(makeIdentity(), hint: Enrollment.Hint(provider: "token2", enrollTo: .cert))), "enrolled real-id token")
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\") to token with token2")
    }

    func testTypeHintAfterAskingForProvider() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        ui.provider = "both"
        XCTAssertEqual(describe(run(makeIdentity(), hint: Enrollment.Hint(provider: nil, enrollTo: .token))), "enrolled real-id token")
        XCTAssertEqual(ui.calls, ["chooseProvider [\"both\", \"token2\"]", "authFinished"])
    }

    func testCancelType() {
        sdk.providers = both
        XCTAssertEqual(describe(run(makeIdentity())), "cancelled")
        XCTAssertEqual(sdk.calls.count, 1)
    }

    func testCancelProvider() {
        sdk.providers = [Enrollment.Provider(name: "a", canCert: true, canToken: false),
                         Enrollment.Provider(name: "b", canCert: true, canToken: false)]
        XCTAssertEqual(describe(run(makeIdentity())), "cancelled")
        XCTAssertEqual(ui.calls, ["chooseProvider [\"a\", \"b\"]"])
    }

    // MARK: - Provider remembered for login

    func testChosenProviderRemembered() {
        sdk.providers = both + [Enrollment.Provider(name: "token2", canCert: false, canToken: true)]
        ui.provider = "token2"
        let zid = makeIdentity()
        _ = run(zid)
        XCTAssertEqual(zid.enrollProvider, "token2")
    }

    func testOnlyProviderRemembered() {
        sdk.providers = [Enrollment.Provider(name: "okta", canCert: true, canToken: false)]
        let zid = makeIdentity()
        _ = run(zid)
        XCTAssertEqual(zid.enrollProvider, "okta")
    }

    func testProviderRememberedWhenBasic() {
        sdk.providers = both + [Enrollment.Provider(name: "legacy", canCert: false, canToken: false)]
        ui.provider = "legacy"
        let zid = makeIdentity()
        XCTAssertEqual(describe(run(zid)), "enrolled real-id none")
        XCTAssertEqual(zid.enrollProvider, "legacy")
    }

    func testProviderRememberedAfterBasicFallback() {
        sdk.providers = both
        ui.enrollTo = .token
        ui.confirm = true
        sdk.enrollToResult = (nil, Enrollment.Failure(message: "exists", alreadyEnrolled: true))
        let zid = makeIdentity()
        XCTAssertEqual(describe(run(zid)), "enrolled real-id none")
        XCTAssertEqual(zid.enrollProvider, "both")
    }

    func testNoProviderRememberedWithoutChoice() {
        sdk.providers = [Enrollment.Provider(name: "a", canCert: false, canToken: false)]
        let zid = makeIdentity()
        XCTAssertEqual(describe(run(zid)), "enrolled real-id none")
        XCTAssertNil(zid.enrollProvider)
    }

    func testProviderNotRememberedUnlessEnrolled() {
        sdk.providers = both
        let cancelled = makeIdentity()
        XCTAssertEqual(describe(run(cancelled)), "cancelled")
        XCTAssertNil(cancelled.enrollProvider)

        ui.enrollTo = .cert
        sdk.result = (nil, Enrollment.Failure(message: "denied", alreadyEnrolled: false))
        let failed = makeIdentity()
        XCTAssertEqual(describe(run(failed)), "failed denied")
        XCTAssertNil(failed.enrollProvider)
    }

    func testFailure() {
        sdk.result = (nil, Enrollment.Failure(message: "bad token", alreadyEnrolled: false))
        XCTAssertEqual(describe(run(makeIdentity())), "failed bad token")
        sdk.result = (nil, nil)
        XCTAssertEqual(describe(run(makeIdentity())), "failed invalid response")
    }

    func testAlreadyEnrolledFallsBackToBasic() {
        sdk.providers = both
        ui.enrollTo = .cert
        ui.confirm = true
        sdk.enrollToResult = (nil, Enrollment.Failure(message: "exists", alreadyEnrolled: true))
        XCTAssertEqual(describe(run(makeIdentity())), "enrolled real-id none")
        XCTAssertEqual(ui.calls, ["chooseEnrollTo", "authFinished", "confirm Device Certificate Enrollment Failed"])
        XCTAssertEqual(sdk.calls.last, "enroll controller(\"https://ctrl.example.com\")")
    }

    func testAlreadyEnrolledDeclined() {
        sdk.providers = both
        ui.enrollTo = .token
        sdk.enrollToResult = (nil, Enrollment.Failure(message: "exists", alreadyEnrolled: true))
        XCTAssertEqual(describe(run(makeIdentity())), "cancelled")
        XCTAssertEqual(ui.calls.last, "confirm User Session Enrollment Failed")
    }

    func testMfaAppliedOnSuccess() {
        sdk.providers = both
        ui.enrollTo = .cert
        ui.mfaCode = "123456"
        sdk.mfaCodeError = .some("wrong code")
        let zid = makeIdentity()
        _ = run(zid)
        XCTAssertEqual(ui.calls, ["chooseEnrollTo", "mfaCode wrong code", "authFinished"])
        XCTAssertTrue(zid.isMfaVerified)
        XCTAssertFalse(zid.isMfaPending)
        XCTAssertNotNil(zid.lastMfaAuth)
    }

    func testMfaNotAppliedOnFailure() {
        sdk.providers = both
        ui.enrollTo = .cert
        ui.mfaCode = "123456"
        sdk.mfaCodeError = .some(nil)
        sdk.result = (nil, Enrollment.Failure(message: "denied", alreadyEnrolled: false))
        let zid = makeIdentity()
        XCTAssertEqual(describe(run(zid)), "failed denied")
        XCTAssertFalse(zid.isMfaEnabled)
        XCTAssertNil(zid.lastMfaAuth)
    }

    func testMfaNotAppliedAfterBasicFallback() {
        sdk.providers = both
        ui.enrollTo = .cert
        ui.confirm = true
        ui.mfaCode = "123456"
        sdk.mfaCodeError = .some(nil)
        sdk.enrollToResult = (nil, Enrollment.Failure(message: "exists", alreadyEnrolled: true))
        let zid = makeIdentity()
        XCTAssertEqual(describe(run(zid)), "enrolled real-id none")
        XCTAssertFalse(zid.isMfaEnabled)
        XCTAssertNil(zid.lastMfaAuth)
    }

    // MARK: - Allowed CAs

    private var allowRootA:CABundlePolicy {
        return CABundlePolicy([CABundlePolicy.fingerprint(CABundlePolicy.certificates(CAFixtures.rootA)!.first!)])
    }

    /// One-time token enrollment whose identity comes back with `ca`
    private func runOtt(ca:String?, currentPolicy:(() -> Enrollment.Policy)? = nil) throws -> Enrollment.Result {
        let jwtFile = NSTemporaryDirectory() + UUID().uuidString + ".jwt"
        try "jwt".write(toFile: jwtFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: jwtFile) }

        let resp = CZiti.ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl"])
        resp.ca = ca
        sdk.result = (resp, nil)
        return run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "ott"]), jwtFile: jwtFile, policy: allowRootA,
                   currentPolicy: currentPolicy)
    }

    // Before the tunnel configuration loads, whether a policy applies isn't known, so nothing is enrolled
    func testUnknownPolicyEnrollsNothing() throws {
        XCTAssertEqual(describe(try runOtt(ca: CAFixtures.rootA, currentPolicy: { .unknown })), "failed \(Enrollment.policyUnknownMessage)")
        XCTAssertEqual(sdk.calls, [])

        let jwtFile = try networkJwt()
        sdk.providers = both
        let result = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"]), jwtFile: jwtFile,
                         currentPolicy: { .unknown })
        XCTAssertEqual(describe(result), "failed \(Enrollment.policyUnknownMessage)")
        XCTAssertEqual(sdk.calls, [])
        XCTAssertEqual(ui.calls, [])

        let byURL = run(makeIdentity(ztAPIs: ["https://ctrl.example.com"]), currentPolicy: { .unknown })
        XCTAssertEqual(describe(byURL), "failed \(Enrollment.policyUnknownMessage)")
        XCTAssertEqual(sdk.calls, [])
    }

    // A profile can arrive while the user signs in: the result is checked against the policy at the end
    func testPolicyReadAgainWhenEnrollmentFinishes() throws {
        var asked = 0
        let restrictsLater:() -> Enrollment.Policy = {
            asked += 1
            return asked == 1 ? .unrestricted : .restricted(self.allowRootA)
        }
        XCTAssertEqual(describe(try runOtt(ca: CAFixtures.rootB, currentPolicy: restrictsLater)), "refused")
        XCTAssertEqual(sdk.calls.filter { $0 == "discard real-id" }.count, 1)
        XCTAssertEqual(asked, 2)
    }

    // a backstop: the callers' policy can't turn unknown once known, but if it did, a spent one-time token leaves nothing
    // to try again with, so nothing is kept
    func testPolicyUnknownWhenEnrollmentFinishes() throws {
        var asked = 0
        let lostLater:() -> Enrollment.Policy = {
            asked += 1
            return asked == 1 ? .unrestricted : .unknown
        }
        XCTAssertEqual(describe(try runOtt(ca: CAFixtures.rootA, currentPolicy: lostLater)),
                       "refused \(Enrollment.policyUnknownAfterEnrollingMessage)")
        XCTAssertEqual(sdk.calls.filter { $0 == "discard real-id" }.count, 1)
    }

    func testPolicyLiftedDuringEnrollment() throws {
        var asked = 0
        let liftsLater:() -> Enrollment.Policy = {
            asked += 1
            return asked == 1 ? .restricted(self.allowRootA) : .unrestricted
        }
        XCTAssertEqual(describe(try runOtt(ca: CAFixtures.rootB, currentPolicy: liftsLater)), "enrolled real-id none")
        XCTAssertFalse(sdk.calls.contains("discard real-id"))
    }

    func testAllowedNetworkEnrolls() throws {
        XCTAssertEqual(describe(try runOtt(ca: CAFixtures.interA + "\n" + CAFixtures.rootA)), "enrolled real-id none")
        XCTAssertFalse(sdk.calls.contains("discard real-id"))
    }

    func testOtherNetworkDiscarded() throws {
        XCTAssertEqual(describe(try runOtt(ca: CAFixtures.rootB)), "refused")
        XCTAssertEqual(sdk.calls.filter { $0 == "discard real-id" }.count, 1)
        XCTAssertEqual(describe(try runOtt(ca: nil)), "refused")
        XCTAssertEqual(sdk.calls.filter { $0 == "discard real-id" }.count, 2)
    }

    private func bootstrapResult(ca:String?) -> (CZiti.ZitiIdentity?, Enrollment.Failure?) {
        let resp = CZiti.ZitiIdentity(id: "bootstrap-id", ztAPIs: ["https://ctrl"])
        resp.ca = ca
        return (resp, nil)
    }

    private func networkJwt() throws -> String {
        let jwtFile = NSTemporaryDirectory() + UUID().uuidString + ".jwt"
        try "jwt".write(toFile: jwtFile, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: jwtFile) }
        return jwtFile
    }

    // A network JWT or controller URL is checked from its bootstrap bundle, before providers or a sign-in
    func testOutsideNetworkJwtRefusedBeforeSignIn() throws {
        let jwtFile = try networkJwt()
        sdk.result = bootstrapResult(ca: CAFixtures.rootB)
        sdk.providers = both
        let result = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"]), jwtFile: jwtFile,
                         hint: Enrollment.Hint(provider: "both", enrollTo: .cert), policy: allowRootA)
        XCTAssertEqual(describe(result), "refused")
        XCTAssertEqual(sdk.calls, ["enroll jwt(\"\(jwtFile)\")"])
        XCTAssertEqual(ui.calls, [])
    }

    func testOutsideControllerURLRefusedBeforeSignIn() {
        sdk.result = bootstrapResult(ca: CAFixtures.rootB)
        sdk.providers = both
        let result = run(makeIdentity(ztAPIs: ["https://ctrl.example.com"]), policy: allowRootA)
        XCTAssertEqual(describe(result), "refused")
        XCTAssertEqual(sdk.calls, ["enroll controller(\"https://ctrl.example.com\")"])
        XCTAssertEqual(ui.calls, [])
    }

    func testAllowedNetworkJwtContinuesAfterBootstrap() throws {
        let jwtFile = try networkJwt()
        sdk.result = bootstrapResult(ca: CAFixtures.rootA)
        sdk.providers = both
        let enrolled = CZiti.ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl"])
        enrolled.ca = CAFixtures.interA + "\n" + CAFixtures.rootA
        sdk.enrollToResult = (enrolled, nil)
        let result = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"]), jwtFile: jwtFile,
                         hint: Enrollment.Hint(provider: "both", enrollTo: .cert), policy: allowRootA)
        XCTAssertEqual(describe(result), "enrolled real-id cert")
        XCTAssertEqual(sdk.calls, ["enroll jwt(\"\(jwtFile)\")", "query jwt(\"\(jwtFile)\")",
                                   "enroll jwt(\"\(jwtFile)\") to cert with both"])
    }

    // Enrolling without a provider is the bootstrap enrollment again, so its result is used rather than fetched twice
    func testAllowedNetworkWithoutProvidersEnrollsOnce() throws {
        let jwtFile = try networkJwt()
        sdk.result = bootstrapResult(ca: CAFixtures.rootA)
        sdk.providers = nil
        let result = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"]), jwtFile: jwtFile, policy: allowRootA)
        XCTAssertEqual(describe(result), "enrolled bootstrap-id none")
        XCTAssertEqual(sdk.calls, ["enroll jwt(\"\(jwtFile)\")", "query jwt(\"\(jwtFile)\")"])
    }

    func testBootstrapFailureFailsWithoutQuery() throws {
        let jwtFile = try networkJwt()
        sdk.result = (nil, Enrollment.Failure(message: "no route", alreadyEnrolled: false))
        let result = run(makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"]), jwtFile: jwtFile, policy: allowRootA)
        XCTAssertEqual(describe(result), "failed no route")
        XCTAssertEqual(sdk.calls, ["enroll jwt(\"\(jwtFile)\")"])
    }

    // The bundle after enrollment is still checked: a controller could answer differently once signed in
    func testRefusedAfterEnrollmentKeepsNoMfaOrProvider() throws {
        let jwtFile = try networkJwt()
        sdk.result = bootstrapResult(ca: CAFixtures.rootA)
        sdk.providers = both
        let enrolled = CZiti.ZitiIdentity(id: "real-id", ztAPIs: ["https://ctrl"])
        enrolled.ca = CAFixtures.rootB
        sdk.enrollToResult = (enrolled, nil)
        sdk.mfaCodeError = .some(nil)
        ui.mfaCode = "123456"
        let zid = makeIdentity(claims: ["sub": "s", "iss": "i", "em": "network"])
        let result = run(zid, jwtFile: jwtFile, hint: Enrollment.Hint(provider: "both", enrollTo: .token), policy: allowRootA)
        XCTAssertEqual(describe(result), "refused")
        XCTAssertTrue(sdk.calls.contains("discard real-id"))
        XCTAssertFalse(zid.isMfaEnabled)
        XCTAssertNil(zid.enrollProvider)
    }
}
