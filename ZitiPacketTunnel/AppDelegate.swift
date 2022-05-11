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
    var menuBar:MainMenuBar? = nil
    
    override init() {
        Logger.initShared(Logger.APP_TAG)
        zLog.info(Version.verboseStr)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuBar = MainMenuBar.shared
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

