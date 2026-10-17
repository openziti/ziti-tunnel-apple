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
    var launchURL:URL?

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

    func notifyNewURL(_ url:URL) {
        let dict:[String: URL] = ["url": url]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "NewURL"), object: nil, userInfo: dict)
    }
}
