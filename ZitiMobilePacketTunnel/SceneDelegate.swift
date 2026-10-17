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

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var launchURL:URL?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // window is initialized automatically from the Main storyboard via UISceneStoryboardFile
        guard let _ = (scene as? UIWindowScene) else { return }

        // Posted once active, when the main view is observing
        if let url = connectionOptions.urlContexts.first?.url {
            zLog.info("Launching app with URL: \(url.absoluteString)")
            launchURL = url
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        zLog.info("SceneDelegate notifying new URL: \(url.absoluteURL)")
        notifyNewURL(url)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let url = launchURL {
            notifyNewURL(url)
            launchURL = nil
        }
    }

    private func notifyNewURL(_ url:URL) {
        let dict:[String: URL] = ["url": readableURL(url)]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "NewURL"), object: nil, userInfo: dict)
    }

    /// Files opened in place are security-scoped, so they're only readable while accessed. Returns a copy
    /// that can be read later, or the URL itself when it isn't security-scoped (e.g., a file iOS already copied).
    private func readableURL(_ url:URL) -> URL {
        guard url.isFileURL, url.startAccessingSecurityScopedResource() else { return url }
        defer { url.stopAccessingSecurityScopedResource() }

        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        var copied = false
        var coordError:NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            do {
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: readURL, to: copy)
                copied = true
            } catch {
                zLog.error("Unable to copy \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let coordError = coordError {
            zLog.error("Unable to read \(url.lastPathComponent): \(coordError.localizedDescription)")
        }
        return copied ? copy : url
    }
}
