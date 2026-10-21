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

/// A link that adds and enrolls an identity: `ziti://enroll?controller=<URL>` (same as adding by URL)
/// or `ziti://enroll?jwt=<network JWT>`, optionally with `provider=<name>` and `type=cert|token` to skip
/// those choices. One-time token JWTs are secrets and aren't accepted.
struct EnrollmentLink : Equatable {
    enum Source : Equatable {
        case controller(URL), jwt(String)
    }

    static let scheme = "ziti"

    let source:Source
    let controller:URL
    let hint:Enrollment.Hint

    init?(_ url:URL) {
        guard url.scheme?.lowercased() == EnrollmentLink.scheme, url.host?.lowercased() == "enroll",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let value = { (name:String) in items.first { $0.name == name }?.value }

        switch (value("controller"), value("jwt")) {
        case (let ctrl?, nil):
            guard let ctrlUrl = EnrollmentLink.controllerURL(ctrl) else { return nil }
            source = .controller(ctrlUrl)
            controller = ctrlUrl
        case (nil, let jwt?):
            guard let claims = EnrollmentLink.claims(jwt), claims["em"] as? String == "network",
                  let iss = claims["iss"] as? String, let ctrlUrl = EnrollmentLink.controllerURL(iss) else { return nil }
            source = .jwt(jwt)
            controller = ctrlUrl
        default:
            return nil
        }

        var enrollTo:ZitiIdentity.EnrollTo?
        if let type = value("type") {
            guard type == "cert" || type == "token" else { return nil }
            enrollTo = ZitiIdentity.EnrollTo(rawValue: type)
        }
        hint = Enrollment.Hint(provider: value("provider"), enrollTo: enrollTo)
    }

    /// Host, plus the port when given, to show the user before enrolling
    var controllerName:String {
        guard let host = controller.host else { return controller.absoluteString }
        if let port = controller.port { return "\(host):\(port)" }
        return host
    }

    /// The URL without its query, for logging
    static func redacted(_ url:URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.scheme ?? "" }
        comps.query = nil
        comps.fragment = nil
        return comps.string ?? url.scheme ?? ""
    }

    private static func controllerURL(_ str:String) -> URL? {
        guard let url = URL(string: str), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil else { return nil }
        return url
    }

    private static func claims(_ jwt:String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension Array where Element == ZitiIdentity {
    mutating func insertFromLink(_ link:EnrollmentLink, _ zidStore:ZitiIdentityStore, at:Int) throws {
        switch link.source {
        case .controller(let url):
            // links are easy to open twice
            guard self.first(where:{$0.id == url.host}) == nil else {
                throw ZitiError("Identity \(link.controllerName) is already present")
            }
            try insertFromURL(url, zidStore, at: at)
        case .jwt(let jwt):
            // the file name becomes the identity name until enrolled
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(link.controller.host ?? "identity").jwt")
            try jwt.write(to: file, atomically: true, encoding: .utf8)
            try insertFromJWT(file, zidStore, at: at)
        }
    }
}
