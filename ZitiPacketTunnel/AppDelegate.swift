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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar:MainMenuBar? = nil;
    
    let statusItem =  NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength);
    let popover = NSPopover();

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuBar = MainMenuBar.shared;
        
       //if let button = statusItem.button {
       //     button.image = NSImage(named: "zitiwhite");
        //    button.image?.size = NSMakeSize(18.0, 18.0);
       //     button.action = #selector(showApp(_:))
       // }
        popover.contentViewController = DashboardScreen.freshController();
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if (popover.isShown) {
            closePopover(sender: sender);
        } else {
            showPopover(sender: sender);
        }
    }
    
    func showPopover(sender: Any?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY);
        }
    }
    
    func closePopover(sender: Any?) {
        popover.performClose(sender);
    }
}

