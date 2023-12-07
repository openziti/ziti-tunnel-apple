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
import NetworkExtension

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar:MainMenuBar? = nil
    
    override init() {
        Logger.initShared(Logger.APP_TAG)
        zLog.info(Version.verboseStr)
    }
    
//    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
//        // hack to simulate menuBar being opened
//        menuBar?.menuDidBeginTracking(n: Notification(name: Notification.Name(rawValue: "DockMenuOpened")))
//        return menuBar?.statusItem.menu
//    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        UserNotifications.shared.requestAuth()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuBar = MainMenuBar.shared
        
        // This is a workaround for a bug we haven't yet fixed where the tunnel is disconnected (no crash log) before waking up from sleep.
        // Attempting to restart on NSWorkspace.didWakeNotification is unreliable, since private key in keystore can't be accessed unless
        // user interaction is available (timing issue). NSApplicationProtectedDataWillBecomeUnavailable / NSApplicationProtectedDataDidBecomeAvailable
        // didn't do the trick, so performing the check on screen unlock.  None of these "solutions" are ideal or fully reliable, but until
        // we address the core issue this will improve the experience of some users.
        DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsLocked"), object:nil, queue: OperationQueue.main) { _ in
            let statusAtLock = TunnelMgr.shared.status
            var unlockObserver:Any?
            unlockObserver = DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                                                               object:nil, queue: OperationQueue.main) { _ in
                if statusAtLock == .connected && statusAtLock != TunnelMgr.shared.status {
                    DispatchQueue.main.async {
                        do {
                            zLog.warn("Restarting tunnel that disconnected while locked")
                            try TunnelMgr.shared.startTunnel()
                        } catch {
                            zLog.error("Unable to start tunnel: \(error.localizedDescription)")
                        }
                    }
                }
                if let unlockObserver = unlockObserver {
                    DistributedNotificationCenter.default.removeObserver(unlockObserver)
                }
            }
        }
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

