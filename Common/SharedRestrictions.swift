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

/// Restrictions the app passes on to the share extension, which can't read the app's managed configuration or its
/// tunnel configuration. The app saves them in the app group each time it reads those. No file means no restrictions.
enum SharedRestrictions {
    // the same key as ManagedConfig's, which the share extension doesn't compile
    private static let DISABLE_ADD_IDENTITY_KEY = "disableAddIdentity"
    private static let ALLOWED_CAS_KEY = "allowedCAs"

    /// Here rather than on ManagedConfig so the share extension can show it too
    static let addDisabledMessage = "Adding identities is turned off by your organization."

    static var url:URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)?
            .appendingPathComponent("restrictions.plist", isDirectory: false)
    }

    static func save(addIdentityDisabled:Bool, to url:URL) {
        update(url) { $0[DISABLE_ADD_IDENTITY_KEY] = addIdentityDisabled ? true : nil }
    }

    static func save(caBundlePolicy:CABundlePolicy?, to url:URL) {
        update(url) { $0[ALLOWED_CAS_KEY] = caBundlePolicy.map { $0.fingerprints.sorted() } }
    }

    static func isAddIdentityDisabled(at url:URL) -> Bool {
        return read(url)[DISABLE_ADD_IDENTITY_KEY] as? Bool ?? false
    }

    static func caBundlePolicy(at url:URL) -> CABundlePolicy? {
        return (read(url)[ALLOWED_CAS_KEY] as? [String]).map { CABundlePolicy($0) }
    }

    private static func read(_ url:URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return [:] }
        return dict
    }

    /// Called whenever a configuration might have changed, so only writes when something did. No restrictions, no file
    private static func update(_ url:URL, _ change:(inout [String: Any]) -> Void) {
        let current = read(url)
        var restrictions = current
        change(&restrictions)
        guard !NSDictionary(dictionary: restrictions).isEqual(to: current) else { return }
        do {
            if restrictions.isEmpty {
                try FileManager.default.removeItem(at: url)
            } else {
                let data = try PropertyListSerialization.data(fromPropertyList: restrictions, format: .xml, options: 0)
                try data.write(to: url, options: .atomic)
            }
        } catch {
            zLog.error("Unable to save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
