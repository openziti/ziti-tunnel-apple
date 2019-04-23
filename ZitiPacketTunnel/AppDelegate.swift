//
//  AppDelegate.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Ziti"
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    let showHideItem = NSMenuItem(title: "Show Control Panel", action: #selector(AppDelegate.showPanel(_:)), keyEquivalent: "Z")
    
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        if let isMin = NSApplication.shared.mainWindow?.isMiniaturized, isMin == false {
            showHideItem.title = "Hide Control Panel"
        }
        getMainWindow()?.delegate = self
        menu.addItem(showHideItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
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
        print("*** should close?")
        if let window = getMainWindow() {
            window.miniaturize(self)
        }
        return false
    }
    
    func windowDidMiniaturize(_ notification: Notification) {
        print("minimized")
        showHideItem.title = "Show Control Panel"
    }
    
    func windowDidDeminiaturize(_ notification: Notification) {
        print("deminiturized")
        showHideItem.title = "Hide Control Panel"
    }
    
    @objc func showPanel(_ sender: Any?) {
        // TODO: NSWindowDelegate (for windowWillClose and friends)
        if let window = getMainWindow() {
            print("Window is visible = \(window.isVisible)")
            if window.isMiniaturized {
                window.deminiaturize(self)
            } else {
                window.miniaturize(self)
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Override point for customization after application launch.
        statusItem.button?.image = NSImage(named:NSImage.Name("StatusBarButtonImage"))
        statusItem.menu = makeMenu()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

