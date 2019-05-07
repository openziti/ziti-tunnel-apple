//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var launchURL:URL?
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Logger.initShared(Logger.APP_TAG)
        NSLog(Version.verboseStr)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let opts = launchOptions {
            launchURL = opts[UIApplication.LaunchOptionsKey.url] as? URL
            NSLog("Launching app with URL: \(launchURL?.absoluteString ?? "invalid")")
        }
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if launchURL == nil {
            NSLog("AppDelegate notifying new URL: \(url.absoluteURL)")
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

