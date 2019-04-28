//
//  AppDelegate.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar:MainMenuBar? = nil

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuBar = MainMenuBar.shared
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

