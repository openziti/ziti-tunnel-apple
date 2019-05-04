//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
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

