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

import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar:MainMenuBar? = nil
    
    override init() {
        Logger.initShared(Logger.APP_TAG)
        zLog.info(Version.verboseStr)
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        UserNotifications.shared.requestAuth()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuBar = MainMenuBar.shared
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

extension AppDelegate : UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        zLog.debug("willPresent: \(notification.request.content.subtitle), \(notification.request.content.body)")
        completionHandler([.list, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        zLog.debug("didReceive: \(response.notification.request.content.subtitle), \(response.notification.request.content.body)")
        zLog.info("didReceive: \(response.debugDescription)")
        completionHandler()
    }
}

