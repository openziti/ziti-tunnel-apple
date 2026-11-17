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

/// Settings an organization sets for the app (managed app configuration): networks to add, each as the fields of
/// an enrollment link, and whether users can add or remove identities.
struct ManagedConfig : Equatable {
    static let NETWORKS_KEY = "networks"
    static let DISABLE_ADD_IDENTITY_KEY = "disableAddIdentity"
    static let DISABLE_REMOVE_IDENTITY_KEY = "disableRemoveIdentity"
    static let keys = [NETWORKS_KEY, DISABLE_ADD_IDENTITY_KEY, DISABLE_REMOVE_IDENTITY_KEY]

    static let removeDisabledMessage = "Removing this identity is turned off by your organization."

    let networks:[EnrollmentLink]
    let disableAddIdentity:Bool
    let disableRemoveIdentity:Bool

    /// nil when none of the keys are set. Invalid values are logged and ignored
    init?(_ value:(String) -> Any?) {
        guard ManagedConfig.keys.contains(where: { value($0) != nil }) else { return nil }
        networks = ManagedConfig.networks(value(ManagedConfig.NETWORKS_KEY))
        disableAddIdentity = ManagedConfig.flag(value, ManagedConfig.DISABLE_ADD_IDENTITY_KEY)
        disableRemoveIdentity = ManagedConfig.flag(value, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY)
    }

    init?(_ dict:[String: Any]) {
        self.init { dict[$0] }
    }

    static func current(_ defaults:UserDefaults = .standard) -> ManagedConfig? {
        return ManagedConfig { defaults.managedValue(forKey: $0) }
    }

    /// Identities on a managed network's controller, enrolled or not
    func isManaged(_ zid:ZitiIdentity) -> Bool {
        return networks.contains { ManagedConfig.isOnController(zid, $0) }
    }

    func canRemove(_ zid:ZitiIdentity) -> Bool {
        return !disableRemoveIdentity || !isManaged(zid)
    }

    /// The provider and enrollment type set for the identity's network, if any
    func hint(for zid:ZitiIdentity) -> Enrollment.Hint {
        return networks.first { ManagedConfig.isOnController(zid, $0) }?.hint ?? Enrollment.Hint()
    }

    /// What's set, without values, for the log and the status summary
    var description:String {
        var parts = ["\(networks.count) network\(networks.count == 1 ? "" : "s")"]
        if disableAddIdentity { parts.append("adding identities turned off") }
        if disableRemoveIdentity { parts.append("removing managed identities turned off") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Parsing

    private static let networkFields = ["controller", "jwt", "provider", "type"]

    private static func networks(_ obj:Any?) -> [EnrollmentLink] {
        guard let obj = obj else { return [] }
        guard let entries = obj as? [Any] else {
            zLog.warn("Ignoring managed \(NETWORKS_KEY): not a list")
            return []
        }
        var links:[EnrollmentLink] = []
        for (i, entry) in entries.enumerated() {
            // a field of the wrong type makes the entry invalid, rather than being treated as missing
            guard let dict = entry as? [String: Any],
                  dict.allSatisfy({ !networkFields.contains($0.key) || $0.value is String }),
                  let link = EnrollmentLink(controller: dict["controller"] as? String, jwt: dict["jwt"] as? String,
                                            provider: dict["provider"] as? String, type: dict["type"] as? String) else {
                zLog.warn("Ignoring invalid managed network \(i + 1)")
                continue
            }
            guard !links.contains(where: { endpoint($0.controller) == endpoint(link.controller) }) else {
                zLog.warn("Ignoring managed network \(i + 1): same controller as an earlier one")
                continue
            }
            links.append(link)
        }
        return links
    }

    private static func flag(_ value:(String) -> Any?, _ key:String) -> Bool {
        guard let obj = value(key) else { return false }
        guard let flag = ProviderConfig.boolValue(obj) else {
            zLog.warn("Ignoring invalid managed \(key)")
            return false
        }
        return flag
    }

    // MARK: - Matching identities to networks

    /// Host and port, with the https default, so "https://ctrl" and "https://ctrl:443/edge/client/v1" match
    private static func endpoint(_ url:URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return "\(host):\(url.port ?? 443)"
    }

    fileprivate static func isOnController(_ zid:ZitiIdentity, _ link:EnrollmentLink) -> Bool {
        guard let czid = zid.czid, let target = endpoint(link.controller) else { return false }
        return ([czid.ztAPI] + (czid.ztAPIs ?? [])).contains { URL(string: $0).flatMap(endpoint) == target }
    }
}

extension Array where Element == ZitiIdentity {
    /// Adds a pending identity for each managed network that doesn't have an identity yet, enrolled or not.
    /// Returns how many were added
    mutating func insertManaged(_ config:ManagedConfig, _ zidStore:ZitiIdentityStore) -> Int {
        var added = 0
        for link in config.networks where !contains(where: { ManagedConfig.isOnController($0, link) }) {
            do {
                try insertFromLink(link, zidStore, at: 0)
                added += 1
            } catch {
                zLog.error("Unable to add identity for managed network \(link.controllerName): \(error.localizedDescription)")
            }
        }
        return added
    }
}

extension UserDefaults {
    static let MANAGED_CONFIGURATION_KEY = "com.apple.configuration.managed"

    /// A value set by an organization. On macOS, managed preferences share the app's defaults, which users can also
    /// write (`defaults write`), so only forced values count.
    func managedValue(forKey key:String) -> Any? {
#if os(macOS)
        return objectIsForced(forKey: key) ? object(forKey: key) : nil
#else
        return dictionary(forKey: UserDefaults.MANAGED_CONFIGURATION_KEY)?[key]
#endif
    }
}
