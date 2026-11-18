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
struct ManagedConfig : Equatable, CustomStringConvertible {
    static let NETWORKS_KEY = "networks"
    static let DISABLE_ADD_IDENTITY_KEY = "disableAddIdentity"
    static let DISABLE_REMOVE_IDENTITY_KEY = "disableRemoveIdentity"
    static let keys = [NETWORKS_KEY, DISABLE_ADD_IDENTITY_KEY, DISABLE_REMOVE_IDENTITY_KEY]

    static let removeDisabledMessage = "Removing this identity is turned off by your organization."
    static let managedNetworkMessage = "This network is set up by your organization."

    let networks:[EnrollmentLink]
    let disableAddIdentity:Bool
    let disableRemoveIdentity:Bool
    /// What was skipped or corrected while reading, for the app to log when the configuration changes
    let problems:[String]

    /// nil when none of the keys are set. Invalid networks are skipped, and a restriction that isn't a valid boolean
    /// is on, so a mistake doesn't lift it
    init?(_ value:(String) -> Any?) {
        guard ManagedConfig.keys.contains(where: { value($0) != nil }) else { return nil }
        var problems:[String] = []
        networks = ManagedConfig.networks(value(ManagedConfig.NETWORKS_KEY), &problems)
        disableAddIdentity = ManagedConfig.flag(value, ManagedConfig.DISABLE_ADD_IDENTITY_KEY, &problems)
        disableRemoveIdentity = ManagedConfig.flag(value, ManagedConfig.DISABLE_REMOVE_IDENTITY_KEY, &problems)
        self.problems = problems
    }

    init?(_ dict:[String: Any]) {
        self.init { dict[$0] }
    }

    static func current(_ defaults:UserDefaults = .standard) -> ManagedConfig? {
        return ManagedConfig { defaults.managedValue(forKey: $0) }
    }

    /// The managed network an identity belongs to, enrolled or not: the one recorded for it, otherwise one on its
    /// controllers (e.g., an identity added before the configuration)
    func network(for zid:ZitiIdentity) -> EnrollmentLink? {
        if let recorded = zid.managedController.flatMap({ URL(string: $0) }).flatMap(EnrollmentLink.endpoint),
           let link = networks.first(where: { EnrollmentLink.endpoint($0.controller) == recorded }) {
            return link
        }
        return networks.first { zid.isOnController(of: $0) }
    }

    func isManaged(_ zid:ZitiIdentity) -> Bool {
        return network(for: zid) != nil
    }

    func canRemove(_ zid:ZitiIdentity) -> Bool {
        return !disableRemoveIdentity || !isManaged(zid)
    }

    /// With adding turned off, only the organization's networks can be enrolled (not identities added before)
    func canEnroll(_ zid:ZitiIdentity) -> Bool {
        return !disableAddIdentity || isManaged(zid)
    }

    /// A link for one of the organization's networks adds nothing the configuration doesn't
    func manages(_ link:EnrollmentLink) -> Bool {
        let endpoint = EnrollmentLink.endpoint(link.controller)
        return networks.contains { EnrollmentLink.endpoint($0.controller) == endpoint }
    }

    /// The provider and enrollment type set for the identity's network, if any
    func hint(for zid:ZitiIdentity) -> Enrollment.Hint {
        return network(for: zid)?.hint ?? Enrollment.Hint()
    }

    /// What's set, without values, for the log and the status summary
    var description:String {
        var parts = ["\(networks.count) network\(networks.count == 1 ? "" : "s")"]
        if disableAddIdentity { parts.append("adding identities turned off") }
        if disableRemoveIdentity { parts.append("removing managed identities turned off") }
        if !problems.isEmpty { parts.append("\(problems.count) problem\(problems.count == 1 ? "" : "s") (see the app log)") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Parsing

    private static let networkFields = ["controller", "jwt", "provider", "type"]

    private static func networks(_ obj:Any?, _ problems:inout [String]) -> [EnrollmentLink] {
        guard let obj = obj else { return [] }
        guard let entries = obj as? [Any] else {
            problems.append("Ignoring managed \(NETWORKS_KEY): not a list")
            return []
        }
        var links:[EnrollmentLink] = []
        for (i, entry) in entries.enumerated() {
            // a field of the wrong type makes the entry invalid, rather than being treated as missing
            guard let dict = entry as? [String: Any],
                  dict.allSatisfy({ !networkFields.contains($0.key) || $0.value is String }),
                  let link = EnrollmentLink(controller: dict["controller"] as? String, jwt: dict["jwt"] as? String,
                                            provider: dict["provider"] as? String, type: dict["type"] as? String) else {
                problems.append("Ignoring invalid managed network \(i + 1)")
                continue
            }
            guard !links.contains(where: { EnrollmentLink.endpoint($0.controller) == EnrollmentLink.endpoint(link.controller) }) else {
                problems.append("Ignoring managed network \(i + 1): same controller as an earlier one")
                continue
            }
            links.append(link)
        }
        return links
    }

    private static func flag(_ value:(String) -> Any?, _ key:String, _ problems:inout [String]) -> Bool {
        guard let obj = value(key) else { return false }
        guard let flag = ProviderConfig.boolValue(obj) else {
            problems.append("Invalid managed \(key), treating it as true")
            return true
        }
        return flag
    }
}

extension Array where Element == ZitiIdentity {
    /// Adds a pending identity for each managed network that doesn't have an identity yet, enrolled or not, and records
    /// the network on each one, so it stays matched when its controller addresses change. Returns how many were added
    mutating func insertManaged(_ config:ManagedConfig, _ zidStore:ZitiIdentityStore) -> Int {
        var added = 0
        for link in config.networks {
            let controller = link.controller.absoluteString
            if let zid = first(where: { config.network(for: $0) == link }) {
                if zid.managedController != controller {
                    zid.managedController = controller
                    _ = zidStore.update(zid, [.ManagedController])
                }
                continue
            }
            do {
                try insertFromLink(link, zidStore, at: 0)
                self[0].managedController = controller
                _ = zidStore.update(self[0], [.ManagedController])
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
        return managedAppConfiguration?[key]
#endif
    }

    /// iOS: the managed app configuration an MDM delivers. Only the MDM writes it, so every value counts
    var managedAppConfiguration:[String: Any]? {
        return dictionary(forKey: UserDefaults.MANAGED_CONFIGURATION_KEY)
    }
}
