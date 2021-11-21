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
import CZiti

class IdentityListitem: NSView {
    
    @IBOutlet var ToggleLabel: NSTextField!
    @IBOutlet var ToggleButton: NSButton!
    @IBOutlet var IdentityLabel: NSTextField!
    @IBOutlet var ServerUrl: NSTextField!
    @IBOutlet var ServicesLabel: NSTextField!
    @IBOutlet var ServiceCount: NSTextField!
    var zid:ZitiIdentity!;
    var tunnelMgr = TunnelMgr.shared;
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    public func setIdentity(identity:ZitiIdentity) {
        zid = identity;
        if (zid.isEnabled) {
            ToggleLabel.stringValue = "enabled";
            ToggleButton.image = NSImage(named: "on");
        } else {
            ToggleLabel.stringValue = "disabled";
            ToggleButton.image = NSImage(named: "off");
        }
        IdentityLabel.stringValue = zid.name;
        ServerUrl.stringValue = zid.czid?.ztAPI ?? "no network";
        ServiceCount.stringValue = String(zid.services.count);
    }
    
    @IBAction func ToggleClicked(_ sender: NSClickGestureRecognizer) {
        let newState = !zid.isEnabled;
        if (newState) {
            ToggleLabel.stringValue = "enabled";
            ToggleButton.image = NSImage(named: "on");
        } else {
            ToggleLabel.stringValue = "disabled";
            ToggleButton.image = NSImage(named: "off");
        }
        zid.enabled = newState;
        ZidMgr.restartTunnel();
        
    }
}
