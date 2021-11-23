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
import AppKit
import SwiftUI

@IBDesignable
class IdentityListitem: NSView {
    
    @IBOutlet weak var view: NSView!
    
    @IBOutlet var TimeoutImage: NSImageView!
    @IBOutlet var MfaImage: NSImageView!
    @IBOutlet var LockoutImage: NSImageView!
    @IBOutlet var BlueBox: NSBox!
    @IBOutlet var ToggleLabel: NSTextField!
    @IBOutlet var ToggleButton: NSButton!
    @IBOutlet var IdentityLabel: NSTextField!
    @IBOutlet var ServerUrl: NSTextField!
    @IBOutlet var ServicesLabel: NSTextField!
    @IBOutlet var ServiceCount: NSTextField!
    var zid:ZitiIdentity!;
    var tunnelMgr = TunnelMgr.shared;
    var timer = Timer();
    let XIB = "IdentityListItem";
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }
    
    private func setup() {
        let nib = NSNib(nibNamed: XIB, bundle: Bundle(for: type(of: self)));
        nib?.instantiate(withOwner: self, topLevelObjects: nil);
        addSubview(view);
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: 0.0),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0.0),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0.0),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0.0),

        ])
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    public func setIdentity(identity:ZitiIdentity) {
        zid = identity;
        if (zid.isEnabled) {
            ToggleLabel?.stringValue = "enabled";
            ToggleButton?.image = NSImage(named: "on");
        } else {
            ToggleLabel?.stringValue = "disabled";
            ToggleButton?.image = NSImage(named: "off");
        }
        IdentityLabel?.stringValue = zid.name;
        ServerUrl?.stringValue = zid.czid?.ztAPI ?? "no network";
        ServiceCount?.stringValue = String(zid.services.count);
        self.CheckMfaRequiredByChecks();
        if (zid.isMfaEnabled) {
            if (!zid.isMfaVerified) {
                // Needs Authentication opposed to service authorization
                ShowImage(name: "mfa");
            }
        }
    }
    
    public func CheckMfaRequiredByChecks() {
        var needsMfa = 0;
        var hasMfa = 0;
        var totalServices = 0;
        var timeout = Int32(-1);
        for service in self.zid.services {
            totalServices += 1;
            guard let checks = service.postureQuerySets else {
                continue;
            }
            
            for check in checks {
                guard let queries = check.postureQueries else {
                    continue
                }
                
                for query in queries {
                    if (query.queryType == "MFA") {
                        needsMfa += 1;
                        if (query.isPassing!) {
                            hasMfa += 1;
                        } else {
                            guard let remaining = query.timeoutRemaining else {
                                continue
                            }
                            
                            if (remaining>timeout) {
                                timeout = remaining;
                            }
                        }
                    }
                }
            }
        }
        if (needsMfa > 0) {
            if (hasMfa == 0) {
                // Nothin is authorized, show authorize
                self.ShowImage(name: "authorize");
            } else {
                if (timeout > -1) {
                    if (timeout > 0) {
                        if (timeout <= 1200) {
                            // Within 20 minutes, show timing out
                            self.ShowImage(name: "timeout");
                            let available = totalServices - needsMfa;
                            ServicesLabel.stringValue = "\(available)/\(totalServices)";
                        }
                    } else {
                        // All tiemd out, show authorize icon
                        self.ShowImage(name: "authorize");
                    }
                }
            }
        }
    }
    
    public func ShowImage(name: String) {
        BlueBox.isHidden = true;
        ServiceCount.isHidden = true;
        MfaImage.isHidden = true;
        LockoutImage.isHidden = true;
        TimeoutImage.isHidden = true;
        
        if (name == "timeout") {
            TimeoutImage.isHidden = false;
        } else if (name == "authorize") {
            LockoutImage.isHidden = false;
            ServicesLabel.stringValue = "authorize";
        } else if (name == "mfa") {
            MfaImage.isHidden = false;
            ServicesLabel.stringValue = "authenticate";
        } else {
            BlueBox.isHidden = false;
            ServiceCount.isHidden = false;
            ServicesLabel.stringValue = "services";
        }
    }
    
    public func UpdateTimerValues() {
        
    }
    
    @IBAction func ToggleClicked(_ sender: NSClickGestureRecognizer) {
        let newState = !zid.isEnabled;
        if (newState) {
            ToggleLabel?.stringValue = "enabled";
            ToggleButton?.image = NSImage(named: "on");
        } else {
            ToggleLabel?.stringValue = "disabled";
            ToggleButton?.image = NSImage(named: "off");
        }
        zid.enabled = newState;
        TunnelMgr.shared.restartTunnel();
        
    }
}
