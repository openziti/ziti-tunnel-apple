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

class MenuScreen: NSViewController {
    
    @IBOutlet var QuitButton: NSTextField!
    @IBOutlet var CloseButton: NSImageView!
    @IBOutlet weak var Dismiss: NSClickGestureRecognizer!
    @IBOutlet var AdvancedButton: NSStackView!
    @IBOutlet var AboutButton: NSStackView!
    @IBOutlet var FeedbackButton: NSStackView!
    @IBOutlet var SupportButton: NSStackView!
    @IBOutlet var DetachButton: NSStackView!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    @IBAction func DoDismiss(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        exit(0);
    }
    
    @IBAction func ShowFeedback(_ sender: NSClickGestureRecognizer) {
    
    }
    
    @IBAction func ShowSupport(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://openziti.discourse.group")!;
        NSWorkspace.shared.open(url);
    }
    
    
    @IBAction func DetachApp(_ sender: NSClickGestureRecognizer) {
    }
    
    @IBAction func ShowAbout(_ sender: NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let screen = storyBoard.instantiateController(withIdentifier: "AboutScreen") as! AboutScreen;
        self.presentAsSheet(screen);
    }
    
    @IBAction func ShowAdvanced(_ sender: NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let screen = storyBoard.instantiateController(withIdentifier: "AdvancedScreen") as! AdvancedScreen;
        self.presentAsSheet(screen);
    }
    
    override func viewDidLoad() {
        let items = [QuitButton, CloseButton, AdvancedButton, AboutButton, FeedbackButton, SupportButton, DetachButton];
        
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
    
    override func viewWillAppear() {
        self.view.window?.titleVisibility = .hidden
        self.view.window?.titlebarAppearsTransparent = true

        self.view.window?.styleMask.insert(.fullSizeContentView)

        self.view.window?.styleMask.remove(.closable)
        self.view.window?.styleMask.remove(.fullScreen)
        self.view.window?.styleMask.remove(.miniaturizable)
        self.view.window?.styleMask.remove(.resizable)
        
        
        view.window?.isOpaque = false
        view.window?.backgroundColor = NSColor.clear
        view.window?.backgroundColor = NSColor(white: 1, alpha: 0.0)
    }
}

