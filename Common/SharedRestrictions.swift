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

/// Restrictions the app passes on to the share extension, which can't read the app's managed configuration.
/// The app saves them in the app group each time it reads the configuration. No file means no restrictions.
enum SharedRestrictions {
    // the same key as ManagedConfig's, which the share extension doesn't compile
    private static let DISABLE_ADD_IDENTITY_KEY = "disableAddIdentity"

    /// Here rather than on ManagedConfig so the share extension can show it too
    static let addDisabledMessage = "Adding identities is turned off by your organization."

    static var url:URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)?
            .appendingPathComponent("restrictions.plist", isDirectory: false)
    }

    static func save(addIdentityDisabled:Bool, to url:URL) {
        // called whenever the configuration might have changed, so only write when it did
        guard addIdentityDisabled != isAddIdentityDisabled(at: url) else { return }
        guard addIdentityDisabled else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                zLog.error("Unable to remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
            return
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: [DISABLE_ADD_IDENTITY_KEY: true], format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            zLog.error("Unable to save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    static func isAddIdentityDisabled(at url:URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return false }
        return dict[DISABLE_ADD_IDENTITY_KEY] as? Bool ?? false
    }
}
