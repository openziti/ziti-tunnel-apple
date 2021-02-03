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

class StartupScreen: NSViewController {
    
    @IBOutlet var MainView: NSView!
    
    
    override func viewDidLoad() {
        self.view.window?.setFrame(NSRect(x:600,y:20,width: 420, height: 520), display: true);
    }
    
    
    override func viewWillAppear() {
        self.view.window?.titleVisibility = .hidden
        self.view.window?.titlebarAppearsTransparent = true

        self.view.window?.styleMask.insert(.fullSizeContentView)
        self.view.window?.styleMask.remove(.closable)
        self.view.window?.styleMask.remove(.fullScreen)
        self.view.window?.styleMask.remove(.miniaturizable)
        self.view.window?.styleMask.remove(.resizable)
        self.view.window?.isMovableByWindowBackground = true;
        
        self.view.window?.isOpaque = false
        self.view.window?.backgroundColor = NSColor.clear
        self.view.window?.backgroundColor = NSColor(white: 1, alpha: 0.0)
        
        //let newFrame = NSRect(x: 600, y: 20, width: 420, height: 520)
        let effect = NSVisualEffectView(frame: self.view.frame);
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 30.0
        effect.layer?.borderColor = .clear
        
        MainView.layer?.cornerRadius = 100;
        MainView.layer?.masksToBounds = true;
        
        MainView.window?.contentView = effect;
        
        
    }
    
    
}
