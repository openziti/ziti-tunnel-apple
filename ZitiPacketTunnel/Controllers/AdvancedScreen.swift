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

import Foundation
import Cocoa

class AdvancedScreen: NSViewController {
    
    @IBOutlet var BackButton: NSImageView!
    @IBOutlet var CloseButton: NSImageView!
    @IBOutlet var TunnelButton: NSStackView!
    @IBOutlet var ServiceLogButton: NSStackView!
    @IBOutlet var AppLogButton: NSStackView!
    @IBOutlet var LogLevelButton: NSStackView!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    override func viewDidLoad() {
        SetupCursor();
    }
    
    @IBAction func GoBack(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func GoToConfig(_ sender: NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let screen = storyBoard.instantiateController(withIdentifier: "ConfigScreen") as! ConfigScreen;
        self.presentAsSheet(screen);
    }
    
    @IBAction func GoToServiceLogs(_ sender: NSClickGestureRecognizer) {
        openConsole(Logger.TUN_TAG);
    }
    
    @IBAction func GoToAppLogs(_ sender: NSClickGestureRecognizer) {
        openConsole(Logger.APP_TAG);
    }
    
    @IBAction func GoToLogLevel(_ sender: NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let screen = storyBoard.instantiateController(withIdentifier: "LogLevelScreen") as! LogLevelScreen;
        self.presentAsSheet(screen);
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
            alert.runModal()
        }
    }
    
    func SetupCursor() {
        let items = [BackButton, CloseButton, TunnelButton, ServiceLogButton, AppLogButton, LogLevelButton];
        
        pointingHand = NSCursor.pointingHand;
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
            item?.alphaValue = 0.6;
        }

        arrow = NSCursor.arrow
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
            item?.alphaValue = 1.0;
        }
    }
}
