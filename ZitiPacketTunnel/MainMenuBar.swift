//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Cocoa
import NetworkExtension

class MainMenuBar : NSObject, NSWindowDelegate {
    static let shared = MainMenuBar()
    
    let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Ziti"
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    private var tunStatusItem:NSMenuItem!
    private var tunConnectItem:NSMenuItem!
    private var showDocItem:NSMenuItem!
    
    private override init() {
        statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarConnected"))
        super.init()
                
        let menu = NSMenu()
        tunStatusItem = newMenuItem(title:"Status:", action:#selector(MainMenuBar.noop(_:)))
        menu.addItem(tunStatusItem)
        tunConnectItem = newMenuItem(title:"Connect", action:#selector(MainMenuBar.connect(_:)))
        menu.addItem(tunConnectItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(newMenuItem(title: "Manage Tunnels", action: #selector(MainMenuBar.showPanel(_:))))
        showDocItem = newMenuItem(title: "Show In Dock", action: #selector(MainMenuBar.showInDock(_:)))
        showDocItem.state = .on
        menu.addItem(showDocItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(newMenuItem(title: "About \(appName)", action: #selector(MainMenuBar.about(_:))))
        menu.addItem(newMenuItem(title: "Quit \(appName)", action: #selector(MainMenuBar.quit(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        getMainWindow()?.delegate = self
        TunnelMgr.shared.tsChangedCallbacks.append(self.tunnelStatusDidChange)
    }
    
    func tunnelStatusDidChange(_ status:NEVPNStatus) {
        switch status {
        case .connecting:
            tunStatusItem.title = "Status: Connecting..."
            tunConnectItem.title = "Disconnect"
            break
        case .connected:
            tunStatusItem.title = "Status: Connected"
            tunConnectItem.title = "Disconnect"
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarConnected"))
            break
        case .disconnecting:
            tunStatusItem.title = "Status: Disconnecting..."
            break
        case .disconnected:
            tunStatusItem.title = "Status: Not Connected"
            tunConnectItem.title = "Connect"
            statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarDisconnected"))
            break
        case .invalid:
            print("Invalid")
            break
        case .reasserting:
            tunStatusItem.title = "Status: Reasserting..."
            break
        @unknown default:
            print("Unknown...")
            break
        }
    }
    
    func newMenuItem(title:String, action:Selector?, keyEquivalent:String="") -> NSMenuItem {
        let mi = NSMenuItem(title:title, action:action, keyEquivalent:keyEquivalent)
        mi.target = self
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
    
    @objc func showPanel(_ sender: Any?) {
        if let window = getMainWindow() {
            window.deminiaturize(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func connect(_ sender: Any?) {
        if tunConnectItem.title == "Connect" {
            try? TunnelMgr.shared.startTunnel()
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
