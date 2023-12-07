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
import NetworkExtension
import CZiti

class MainMenuBar : NSObject, NSWindowDelegate {
    static let shared = MainMenuBar()
    
    let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Ziti"
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    private var menu:NSMenu!
    private var tunStatusItem:NSMenuItem!
    private var tunConnectItem:NSMenuItem!
    private var snapshotItem:NSMenuItem!
    private var showDocItem:NSMenuItem!
    private var logLevelMenu:NSMenu!
    
    private var identityItems:[NSMenuItem] = []
    
    private override init() {
        statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarConnected"))
        super.init()
                
        menu = NSMenu()
        tunStatusItem = newMenuItem(title:"Status:", action:#selector(MainMenuBar.noop(_:)))
        menu.addItem(tunStatusItem)
        tunConnectItem = newMenuItem(title:"Connect", action:#selector(MainMenuBar.connect(_:)))
        menu.addItem(tunConnectItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(newMenuItem(title: "Manage Tunnels", action: #selector(MainMenuBar.showPanel(_:))))
        
        showDocItem = newMenuItem(title: "Show In Dock", action: #selector(MainMenuBar.showInDock(_:)))
        showDocItem.state = .on
        menu.addItem(showDocItem)
        
        // Log Menu
        let logMenuItem = newMenuItem(title: "Logging", action: nil)
        menu.addItem(logMenuItem)
        let logMenu = NSMenu()
        
        logMenu.addItem(newMenuItem(title: "Packet Tunnel...", action: #selector(MainMenuBar.showPacketTunnelLog(_:))))
        logMenu.addItem(newMenuItem(title: "Application...", action: #selector(MainMenuBar.showApplicationLog(_:))))
        logMenu.addItem(NSMenuItem.separator())
        
        logMenu.addItem(newMenuItem(title: "Log Rotation...", action: #selector(MainMenuBar.showLogRotationConfig(_:))))
        logMenu.addItem(NSMenuItem.separator())
                
        let logLevelMenuItem = newMenuItem(title: "Level", action: nil)
        logMenu.addItem(logLevelMenuItem)
        logLevelMenu = NSMenu()
        logLevelMenu.addItem(newMenuItem(title: "FATAL",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.NONE.rawValue)))
        logLevelMenu.addItem(newMenuItem(title: "ERROR",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.ERROR.rawValue)))
        logLevelMenu.addItem(newMenuItem(title: "WARN",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.WARN.rawValue)))
        logLevelMenu.addItem(newMenuItem(title: "INFO",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.INFO.rawValue)))
        logLevelMenu.addItem(newMenuItem(title: "DEBUG",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.DEBUG.rawValue)))
        logLevelMenu.addItem(newMenuItem(title: "VERBOSE",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.VERBOSE.rawValue)))
        logLevelMenu.addItem(newMenuItem(title: "TRACE",
                                         action: #selector(MainMenuBar.selectLogLevel(_:)),
                                         tag: Int(ZitiLog.LogLevel.TRACE.rawValue)))
        logMenu.setSubmenu(logLevelMenu, for: logLevelMenuItem)
        updateLogLevelMenu()
        
        menu.setSubmenu(logMenu, for: logMenuItem)
        // End Log Menu
        
        snapshotItem = newMenuItem(title: "Snapshot...", action: nil)
        menu.addItem(snapshotItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(newMenuItem(title: "About \(appName)", action: #selector(MainMenuBar.about(_:))))
        menu.addItem(newMenuItem(title: "Quit \(appName)", action: #selector(MainMenuBar.quit(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Track the menu, update items as necessary
        NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil, queue: .main, using: menuDidBeginTracking)
        
        getMainWindow()?.delegate = self
        TunnelMgr.shared.tsChangedCallbacks.append(self.tunnelStatusDidChange)
        
        // listen for newOrChanged
        NotificationCenter.default.addObserver(forName: .onNewOrChangedId, object: nil, queue: OperationQueue.main) { [self] notification in
            DispatchQueue.main.async {
                if TunnelMgr.shared.status == .connected {
                    if TunnelMgr.shared.allEnabledZidsFullyAvailable() {
                        self.statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarConnected"))
                    } else {
                        self.statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarAttention"))
                    }
                }
            }
        }
    }
    
    func clearIdentities() {
        identityItems.forEach { item in
            menu.removeItem(item)
        }
        identityItems = []
    }
    
    func menuDidBeginTracking(n: Notification) {
        updateLogLevelMenu()
        
        clearIdentities()
        
        let count = TunnelMgr.shared.zids.count
        if count > 0 {
            var idIndx = 2
            let sepItem = NSMenuItem.separator()
            menu.insertItem(sepItem, at: idIndx)
            identityItems.append(sepItem)
            idIndx += 1
            
            for i in 0...(count-1) {
                let zid = TunnelMgr.shared.zids[i]
                let tunnelStatus = TunnelMgr.shared.status
                var imageName:String = "NSStatusNone"
                var tooltip:String = ""
                
                if zid.isEnabled && zid.isMfaEnabled && zid.isMfaPending {
                    tooltip = " (MFA Pending)"
                } else if !zid.allServicePostureChecksPassing() {
                    tooltip = " (Posture check failing)"
                }
                
                if zid.isEnrolled == true, zid.isEnabled == true, let edgeStatus = zid.edgeStatus {
                    switch edgeStatus.status {
                    case .Available:
                        imageName = (tunnelStatus == .connected) ? "NSStatusAvailable" : "NSStatusPartiallyAvailable"
                    case .PartiallyAvailable:
                        imageName = "NSStatusPartiallyAvailable"
                    case .Unavailable:
                        imageName = "NSStatusUnavailable"
                    default:
                        imageName = "NSStatusNone"
                    }
                    
                    if tunnelStatus != .connected {
                        tooltip = ""
                    }
                }
                let idItem = newMenuItem(title: "\(zid.name)\(tooltip)", action: #selector(MainMenuBar.onIdentity(_:)), tag:i)
                idItem.image = NSImage(named:imageName)
                menu.insertItem(idItem, at: idIndx)
                identityItems.append(idItem)
                idIndx += 1
            }
        }
    }
    
    func tunnelStatusDidChange(_ status:NEVPNStatus) {
        snapshotItem.action = nil
        switch status {
        case .connecting:
            tunStatusItem.title = "Status: Connecting..."
            tunConnectItem.title = "Disconnect"
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarAttention"))
            break
        case .connected:
            tunStatusItem.title = "Status: Connected"
            tunConnectItem.title = "Disconnect"
            snapshotItem.action = #selector(MainMenuBar.showSnapshot(_:))
            
            if TunnelMgr.shared.allEnabledZidsFullyAvailable() {
                statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarConnected"))
            } else {
                statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarAttention"))
            }
            break
        case .disconnecting:
            tunStatusItem.title = "Status: Disconnecting..."
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarAttention"))
            break
        case .disconnected:
            tunStatusItem.title = "Status: Not Connected"
            tunConnectItem.title = "Connect"
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarDisconnected"))
            break
        case .invalid:
            tunStatusItem.title = "Status: Invalid"
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarDisconnected"))
            break
        case .reasserting:
            tunStatusItem.title = "Status: Reasserting..."
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarAttention"))
            break
        @unknown default:
            zLog.warn("Unknown tunnel status...")
            break
        }
    }
    
    func newMenuItem(title:String, action:Selector?, keyEquivalent:String="", tag:Int=0) -> NSMenuItem {
        let mi = NSMenuItem(title:title, action:action, keyEquivalent:keyEquivalent)
        mi.target = self
        mi.tag = tag
        return mi
    }
    
    func getMainWindow() -> NSWindow? {
        // Hack (since NSApplication.shared.mainWindow is nil when minimized)
        for window in NSApplication.shared.windows {
            if window.className == "NSWindow" && window.title == appName {
                return window
            }
        }
        return nil
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(self)
        return false
    }
    
    @objc func onIdentity(_ sender: NSMenuItem?) {
        guard let indx = sender?.tag else {
            zLog.wtf("Unable to retrieve index for selected identity")
            return
        }
        
        let zidCount = TunnelMgr.shared.zids.count
        guard indx >= 0 && indx < zidCount else {
            zLog.wtf("invalid zid indx \(indx), zidCount=\(zidCount)")
            return
        }
        
        let zid = TunnelMgr.shared.zids[indx]
        
        var category = ""
        var action = ""
        if TunnelMgr.shared.status == .connected && zid.isEnabled && zid.isMfaPending {
            category = UserNotifications.Category.Mfa.rawValue
            action = UserNotifications.Action.MfaAuth.rawValue
        }
        let msg = IpcAppexNotificationActionMessage(zid.id, category, action)
        NotificationCenter.default.post(name: .onAppexNotification, object: self, userInfo: ["ipcMessage":msg])
    }
    
    @objc func showInDock(_ sender: Any?) {
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
            showDocItem.state = .off
            if getMainWindow()?.isVisible ?? false {
                DispatchQueue.main.async { self.showPanel(self) }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            showDocItem.state = .on
        }
    }
    
    func openConsole(_ tag:String) {
        guard let logger = Logger.shared, let logFile = logger.currLog(forTag: tag)?.absoluteString else {
            zLog.error("Unable to find path to \(tag) log")
            return
        }
        
        let task = Process()
        task.arguments = ["-b", "com.apple.Console", logFile]
        task.launchPath = "/usr/bin/open"
        task.launch()
        task.waitUntilExit()
        let status = task.terminationStatus
        if (status != 0) {
            zLog.error("Unable to open \(logFile) in com.apple.Console, status=\(status)")
            let alert = NSAlert()
            alert.messageText = "Log Unavailable"
            alert.informativeText = "Unable to open \(logFile) in com.apple.Console"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal() //== .alertFirstButtonReturn
        }
    }
    
    @objc func showPacketTunnelLog(_ sender:Any?) {
        openConsole(Logger.TUN_TAG)
    }
    
    @objc func showApplicationLog(_ sender:Any?) {
        openConsole(Logger.APP_TAG)
    }
    
    @objc func showLogRotationConfig(_ sender:Any?) {
        let sb = NSStoryboard(name: "Main", bundle: nil)
        if let wc = sb.instantiateController(withIdentifier: "LOG_ROTATION_WINDOW") as? NSWindowController {
            if let w = wc.window {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.runModal(for: w)
            }
        }
    }
    
    @objc func showSnapshot(_ sender:Any?) {
        TunnelMgr.shared.ipcClient.sendToAppex(IpcDumpRequestMessage()) { respMsg, zErr in
            guard zErr == nil else {
                zLog.error("Unable to send provider message for snapshot (dump): \(zErr!.localizedDescription)")
                return
            }
            guard let dumpResp = respMsg as? IpcDumpResponseMessage,
                  let str = dumpResp.dump else {
                zLog.error("Unable to parse snapshot (dump) string from response message")
                return
            }
            
            zLog.info(str)
            guard let wc = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "SNAPSHOT_WINDOW") as? NSWindowController else {
                zLog.wtf("Unable to access SNAPSHOT_WINDOW from Main Storyboard")
                return
            }
            
            wc.window?.title = "Ziti Snapshot \(Date())"
            if let vc = wc.contentViewController as? SnapshotViewController {
                vc.textView.textStorage?.mutableString.setString(str)
            }
            wc.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func updateLogLevelMenu() {
        let level = ZitiLog.getLogLevel()
        logLevelMenu.items.forEach { i in
            i.state = Int32(i.tag) == level.rawValue ? .on : .off
        }
    }
    
    @objc func selectLogLevel(_ sender: NSMenuItem?) {
        let raw  = sender != nil ? Int32(sender!.tag) : ZitiLog.LogLevel.INFO.rawValue
        let lvl = ZitiLog.LogLevel(rawValue: raw) ?? ZitiLog.LogLevel.INFO
        TunnelMgr.shared.updateLogLevel(lvl)
        updateLogLevelMenu()
    }
    
    @objc func showPanel(_ sender: Any?) {
        if let window = getMainWindow() {
            window.deminiaturize(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func connect(_ sender: Any?) {
        if tunConnectItem.title == "Connect" {
            do {
                try TunnelMgr.shared.startTunnel()
            } catch {
                zLog.error("Exception staring tunnel: \(error.localizedDescription)")
            }
        } else {
            TunnelMgr.shared.stopTunnel()
        }
    }
    
    @objc func about(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(self)
    }
    
    @objc func quit(_ sender: Any?) {
        NSApp.terminate(self)
    }
    
    @objc func noop(_ sender: Any?) {
    }
}
