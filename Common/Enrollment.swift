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

import Foundation
import CZiti

/// Dialogs and other platform UI used during enrollment. Called on the main queue
protocol EnrollmentUI : AnyObject {
    /// One of `names`, or nil to cancel
    func chooseProvider(_ zid:ZitiIdentity, _ names:[String], _ completion:@escaping (String?) -> Void)
    /// Device Certificate or User Session, or nil to cancel
    func chooseEnrollTo(_ zid:ZitiIdentity, _ completion:@escaping (ZitiIdentity.EnrollTo?) -> Void)
    /// Whether to enroll without cert or token after the network reports an existing identity
    func confirmBasicEnroll(_ info:(title:String, detail:String, action:String), _ completion:@escaping (Bool) -> Void)
    func openAuthURL(_ url:URL, _ completion:@escaping (Bool) -> Void)
    /// Browser authentication (if any) is over and the SDK has returned
    func authFinished()
    func mfaSetup(_ zid:ZitiIdentity, _ provisioningUrl:String, _ error:String?, _ submit:@escaping (String?) -> Void)
    func mfaCode(_ zid:ZitiIdentity, _ error:String?, _ submit:@escaping (String?) -> Void)
    func showError(_ msg:String)
}

/// SDK calls used during enrollment, replaced in tests
protocol EnrollmentSDK {
    typealias Callback = (CZiti.ZitiIdentity?, Enrollment.Failure?) -> Void
    typealias MfaSetupCallback = (_ provisioningUrl:String?, _ error:String?, _ submit:@escaping (String?) -> Void) -> Void
    typealias MfaCodeCallback = (_ error:String?, _ submit:@escaping (String?) -> Void) -> Void

    /// The network's providers, or nil if the query failed
    func queryProviders(_ source:Enrollment.Source, _ cb:@escaping ([Enrollment.Provider]?) -> Void)
    func enroll(_ source:Enrollment.Source, _ cb:@escaping Callback)
    func enroll(_ source:Enrollment.Source, to enrollTo:ZitiIdentity.EnrollTo, provider:String,
                onAuth:@escaping (String) -> Void, onMfaSetup:@escaping MfaSetupCallback, onMfaCode:@escaping MfaCodeCallback,
                _ cb:@escaping Callback)
}

/// Enrolls one identity, shared by macOS and iOS
class Enrollment {
    /// What to enroll with: a one-time token JWT, or a network JWT or controller URL that may offer cert or token enrollment
    enum Source : Equatable {
        case ott(String), jwt(String), controller(String)
    }

    struct Provider : Equatable {
        let name:String
        let canCert:Bool
        let canToken:Bool
    }

    struct Failure : Error {
        let message:String
        let alreadyEnrolled:Bool
    }

    enum Result {
        case enrolled(CZiti.ZitiIdentity, ZitiIdentity.EnrollTo)
        case failed(String)
        case cancelled
    }

    /// Answers to use instead of asking, when they fit what the network offers
    struct Hint : Equatable {
        var provider:String?
        var enrollTo:ZitiIdentity.EnrollTo?
    }

    static func source(jwtFile:String?, method:ZitiIdentity.EnrollmentMethod, controllerURL:String?) -> Source? {
        if let jwtFile = jwtFile {
            return method == .ott ? .ott(jwtFile) : .jwt(jwtFile)
        }
        return controllerURL.map { .controller($0) }
    }

    /// Providers to choose from, or nil when none can enroll to cert or token and only basic enrollment applies
    static func choices(_ providers:[Provider]?) -> [Provider]? {
        guard let providers = providers, providers.contains(where: { $0.canCert || $0.canToken }) else { return nil }
        return providers
    }

    let zid:ZitiIdentity
    private let ui:EnrollmentUI
    private let sdk:EnrollmentSDK
    private let hint:Hint
    private var completion:((Result) -> Void)?
    private var mfaEnabled = false
    private var lastMfaAuth:Date?
    private var provider:String?

    init(_ zid:ZitiIdentity, ui:EnrollmentUI, sdk:EnrollmentSDK = ZitiEnrollmentSDK(), hint:Hint = Hint()) {
        self.zid = zid
        self.ui = ui
        self.sdk = sdk
        self.hint = hint
    }

    /// Completes once, on the main queue. `jwtFile` is where the identity's JWT is kept, if it has one
    func start(jwtFile:String, _ completion:@escaping (Result) -> Void) {
        self.completion = completion
        let jwt = FileManager.default.fileExists(atPath: jwtFile) ? jwtFile : nil
        guard let source = Enrollment.source(jwtFile: jwt, method: zid.getEnrollmentMethod(), controllerURL: zid.czid?.ztAPI) else {
            finish(.failed("No JWT file or controller URL available"))
            return
        }
        if case .ott = source {
            enroll(source)
            return
        }
        DispatchQueue.global().async {
            self.sdk.queryProviders(source) { providers in
                DispatchQueue.main.async { self.choose(source, providers) }
            }
        }
    }

    private func choose(_ source:Source, _ providers:[Provider]?) {
        guard let providers = Enrollment.choices(providers) else {
            enroll(source)
            return
        }
        if providers.count == 1 {
            chosen(source, providers[0])
            return
        }
        if let name = hint.provider {
            if let provider = providers.first(where: { $0.name == name }) {
                chosen(source, provider)
                return
            }
            zLog.warn("Provider \(name.debugDescription) not offered by the network, asking instead")
        }
        ui.chooseProvider(zid, providers.map { $0.name }) { name in
            guard let provider = providers.first(where: { $0.name == name }) else {
                self.finish(.cancelled)
                return
            }
            self.chosen(source, provider)
        }
    }

    /// Enrolls with whatever the provider offers, asking when it offers both cert and token
    private func chosen(_ source:Source, _ provider:Provider) {
        self.provider = provider.name
        switch (provider.canCert, provider.canToken) {
        case (true, true):
            if let enrollTo = hint.enrollTo, enrollTo != .none {
                enroll(source, to: enrollTo, provider: provider.name)
                return
            }
            ui.chooseEnrollTo(zid) { enrollTo in
                guard let enrollTo = enrollTo else {
                    self.finish(.cancelled)
                    return
                }
                self.enroll(source, to: enrollTo, provider: provider.name)
            }
        case (true, false), (false, true):
            let enrollTo:ZitiIdentity.EnrollTo = provider.canCert ? .cert : .token
            if let hinted = hint.enrollTo, hinted != enrollTo {
                zLog.warn("Provider \(provider.name.debugDescription) doesn't offer \(hinted.rawValue) enrollment, using \(enrollTo.rawValue)")
            }
            enroll(source, to: enrollTo, provider: provider.name)
        case (false, false): enroll(source)
        }
    }

    private func enroll(_ source:Source) {
        DispatchQueue.global().async {
            self.sdk.enroll(source, self.once { zidResp, failure in
                guard failure == nil, let zidResp = zidResp else {
                    self.finish(.failed(failure?.message ?? "invalid response"))
                    return
                }
                self.finish(.enrolled(zidResp, .none))
            })
        }
    }

    private func enroll(_ source:Source, to enrollTo:ZitiIdentity.EnrollTo, provider:String) {
        let onAuth:(String) -> Void = { urlString in
            DispatchQueue.main.async {
                guard let url = URL(string: urlString) else {
                    self.ui.showError("Invalid authentication URL: \(urlString)")
                    return
                }
                self.ui.openAuthURL(url) { opened in
                    if !opened {
                        self.ui.showError("Unable to open authentication URL. Please copy and paste into your browser: \(urlString)")
                    }
                }
            }
        }
        let onMfaSetup:EnrollmentSDK.MfaSetupCallback = { provisioningUrl, error, submit in
            DispatchQueue.main.async {
                guard let provisioningUrl = provisioningUrl else {
                    submit(nil)
                    return
                }
                self.ui.mfaSetup(self.zid, provisioningUrl, error) { code in
                    if code != nil { self.mfaEnabled = true }
                    submit(code)
                }
            }
        }
        let onMfaCode:EnrollmentSDK.MfaCodeCallback = { error, submit in
            DispatchQueue.main.async {
                self.ui.mfaCode(self.zid, error) { code in
                    if code != nil {
                        self.mfaEnabled = true
                        self.lastMfaAuth = Date()
                    }
                    submit(code)
                }
            }
        }
        let requestedType = enrollTo == .cert ? "Device Certificate" : "User Session"

        DispatchQueue.global().async {
            self.sdk.enroll(source, to: enrollTo, provider: provider, onAuth: onAuth, onMfaSetup: onMfaSetup, onMfaCode: onMfaCode,
                            self.once { zidResp, failure in
                self.ui.authFinished()
                if let failure = failure {
                    guard failure.alreadyEnrolled else {
                        self.finish(.failed(failure.message))
                        return
                    }
                    self.ui.confirmBasicEnroll(ZitiIdentity.alreadyEnrolledInfo(requestedType: requestedType)) { confirmed in
                        guard confirmed else {
                            self.finish(.cancelled)
                            return
                        }
                        // basic enrollment doesn't do MFA, so drop any from the failed attempt
                        self.mfaEnabled = false
                        self.lastMfaAuth = nil
                        self.enroll(source)
                    }
                    return
                }
                guard let zidResp = zidResp else {
                    self.finish(.failed("invalid response"))
                    return
                }
                self.finish(.enrolled(zidResp, enrollTo))
            })
        }
    }

    /// Delivers the SDK's callback on the main queue, ignoring any repeat
    private func once(_ cb:@escaping EnrollmentSDK.Callback) -> EnrollmentSDK.Callback {
        var called = false
        return { zidResp, failure in
            DispatchQueue.main.async {
                guard !called else { return }
                called = true
                cb(zidResp, failure)
            }
        }
    }

    /// MFA set up or used during enrollment, and the provider chosen, are applied once it succeeds
    private func finish(_ result:Result) {
        if case .enrolled = result {
            zid.enrollProvider = provider
            if mfaEnabled {
                zid.mfaEnabled = true
                zid.mfaVerified = true
                zid.mfaPending = false
                if let lastMfaAuth = lastMfaAuth { zid.lastMfaAuth = lastMfaAuth }
            }
        }
        completion?(result)
        completion = nil
    }
}

struct ZitiEnrollmentSDK : EnrollmentSDK {
    func queryProviders(_ source:Enrollment.Source, _ cb:@escaping ([Enrollment.Provider]?) -> Void) {
        let queryCallback:([ZitiEvent.JwtSigner]?, CZiti.ZitiError?) -> Void = { signers, zErr in
            guard zErr == nil, let signers = signers else {
                cb(nil)
                return
            }
            cb(signers.map { Enrollment.Provider(name: $0.name, canCert: $0.canCertEnroll, canToken: $0.canTokenEnroll) })
        }
        switch source {
        case .ott(let jwtFile), .jwt(let jwtFile): Ziti.queryProviders(jwtFile: jwtFile, cb: queryCallback)
        case .controller(let url): Ziti.queryProviders(controllerURL: url, cb: queryCallback)
        }
    }

    func enroll(_ source:Enrollment.Source, _ cb:@escaping Callback) {
        switch source {
        case .ott(let jwtFile), .jwt(let jwtFile): Ziti.enroll(jwtFile, callback(cb))
        case .controller(let url): Ziti.enroll(controllerURL: url, callback(cb))
        }
    }

    func enroll(_ source:Enrollment.Source, to enrollTo:ZitiIdentity.EnrollTo, provider:String,
                onAuth:@escaping (String) -> Void, onMfaSetup:@escaping MfaSetupCallback, onMfaCode:@escaping MfaCodeCallback,
                _ cb:@escaping Callback) {
        let onMfaEnrollRequired:Ziti.MfaEnrollRequiredCallback = { mfaEnrollment, zErr, submit in
            onMfaSetup(mfaEnrollment.provisioningUrl, zErr?.localizedDescription, submit)
        }
        let onMfaCodeRequired:Ziti.MfaCodeRequiredCallback = { zErr, submit in
            onMfaCode(zErr?.localizedDescription, submit)
        }
        switch (source, enrollTo) {
        case (.ott(let jwtFile), .cert), (.jwt(let jwtFile), .cert):
            Ziti.enrollToCert(jwtFile: jwtFile, provider: provider, onAuth: onAuth,
                              onMfaEnrollRequired: onMfaEnrollRequired, onMfaCodeRequired: onMfaCodeRequired, callback(cb))
        case (.ott(let jwtFile), _), (.jwt(let jwtFile), _):
            Ziti.enrollToToken(jwtFile: jwtFile, provider: provider, onAuth: onAuth,
                               onMfaEnrollRequired: onMfaEnrollRequired, onMfaCodeRequired: onMfaCodeRequired, callback(cb))
        case (.controller(let url), .cert):
            Ziti.enrollToCert(controllerURL: url, provider: provider, onAuth: onAuth,
                              onMfaEnrollRequired: onMfaEnrollRequired, onMfaCodeRequired: onMfaCodeRequired, callback(cb))
        case (.controller(let url), _):
            Ziti.enrollToToken(controllerURL: url, provider: provider, onAuth: onAuth,
                               onMfaEnrollRequired: onMfaEnrollRequired, onMfaCodeRequired: onMfaCodeRequired, callback(cb))
        }
    }

    private func callback(_ cb:@escaping Callback) -> Ziti.EnrollmentCallback {
        return { zidResp, zErr in
            cb(zidResp, zErr.map { Enrollment.Failure(message: $0.localizedDescription, alreadyEnrolled: $0.isAlreadyEnrolled) })
        }
    }
}
