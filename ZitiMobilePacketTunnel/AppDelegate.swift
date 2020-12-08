//
// Copyright 2019-2020 NetFoundry, Inc.
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

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var launchURL:URL?
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Logger.initShared(Logger.APP_TAG)
        zLog.info(Version.verboseStr)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let opts = launchOptions {
            launchURL = opts[UIApplication.LaunchOptionsKey.url] as? URL
            zLog.info("Launching app with URL: \(launchURL?.absoluteString ?? "invalid")")
        }
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if launchURL == nil {
            zLog.info("AppDelegate notifying new URL: \(url.absoluteURL)")
            notifyNewURL(url)
        }
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if let url = launchURL {
            notifyNewURL(url)
            launchURL = nil
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }
    
    func notifyNewURL(_ url:URL) {
        let dict:[String: URL] = ["url": url]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "NewURL"), object: nil, userInfo: dict)
    }
}

