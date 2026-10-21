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
            zLog.info("Launching app with URL: \(EnrollmentLink.redacted(url))")
            launchURL = url
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        zLog.info("SceneDelegate notifying new URL: \(EnrollmentLink.redacted(url))")
        notifyNewURL(url)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let url = launchURL {
            notifyNewURL(url)
            launchURL = nil
        }
    }

    private func notifyNewURL(_ url:URL) {
        // Reading the file can wait on a download (e.g., from iCloud Drive), so copy it off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            var dict:[String: URL] = ["url": url]
            if let copy = self.readableCopy(url) {
                dict["url"] = copy
                dict["tempDir"] = copy.deletingLastPathComponent()
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: "NewURL"), object: nil, userInfo: dict)
            }
        }
    }

    /// Files opened in place are security-scoped, so they're only readable while accessed. Returns a copy
    /// that can be read later, or nil when the file isn't security-scoped (e.g., a file iOS already copied)
    /// or can't be copied. Each copy gets its own directory, keeping the file name (used for the identity name).
    private func readableCopy(_ url:URL) -> URL? {
        guard url.isFileURL, url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        var copied = false
        var coordError:NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: readURL, to: copy)
                copied = true
            } catch {
                zLog.error("Unable to copy \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let coordError = coordError {
            zLog.error("Unable to read \(url.lastPathComponent): \(coordError.localizedDescription)")
        }
        if !copied {
            try? FileManager.default.removeItem(at: dir)
        }
        return copied ? copy : nil
    }
}
