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
import CZiti
import AppKit
import SwiftUI

@IBDesignable
class ServiceListItem: NSView {
    
    @IBOutlet weak var view: NSView!
    
    @IBOutlet var DetailsArea: NSView!
    @IBOutlet var MfaImage: NSImageView!
    @IBOutlet var TimeoutImage: NSImageView!
    @IBOutlet var WarningImage: NSImageView!
    @IBOutlet var ServicePorts: NSTextField!
    @IBOutlet var ServiceProtocols: NSTextField!
    @IBOutlet var ServiceUrl: NSTextField!
    @IBOutlet var ServiceLabel: NSTextField!
    var service:ZitiService!;
    var vc:DashboardScreen!;
    var tunnelMgr = TunnelMgr.shared;
    var timer = Timer();
    let XIB = "ServiceListItem";
    var timeLeft = -1;
    var timeTotal = -1;
    
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
    
    public func SetService(service:ZitiService, vc:DashboardScreen) {
        self.service = service;
        self.vc = vc;
        ServiceLabel.stringValue = service.name ?? "No Name";
        ServiceUrl.stringValue = service.addresses ?? "-";
        ServiceProtocols.stringValue = service.protocols ?? "-";
        ServicePorts.stringValue = service.portRanges ?? "-";
        WarningImage.isHidden = true;
        MfaImage.isHidden = true;
        TimeoutImage.isHidden = true;
        
        for checkSet in service.postureQuerySets ?? [] {
            for posture in checkSet.postureQueries ?? [] {
                let type = posture.queryType ?? "";
                
                if (type == "MFA") {
                    if (!(posture.isPassing ?? true)) {
                        MfaImage.isHidden = false;
                        MfaImage.toolTip =  " \(type) Failing";
                        break;
                    } else {
                        if (posture.timeout! > 0) {
                            if (posture.timeoutRemaining! > 0) {
                                timeLeft = Int(posture.timeoutRemaining ?? 0);
                                timeTotal = Int(posture.timeout ?? 0);
                                timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
                            } else {
                                WarningImage.isHidden = true;
                                MfaImage.isHidden = true;
                                TimeoutImage.isHidden = true;
                                
                                MfaImage.isHidden = false;
                                MfaImage.toolTip =  " \(type) Failing";
                            }
                        }
                    }
                } else {
                    if (!(posture.isPassing ?? true)) {
                        WarningImage.isHidden = false;
                        WarningImage.toolTip =  " \(type) Failing";
                    }
                }
            }
        }
    }
    
    func secondsToHoursMinutesSeconds(_ seconds: Int) -> (Int, Int, Int) {
        return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }
    
    public func SetTimedOut() {
        MfaImage.isHidden = false;
        MfaImage.toolTip =  "MFA Timed Out";
    }
    
    @objc public func UpdateTimer() {
        if (self.timeLeft <= 2800) {
            WarningImage.isHidden = true;
            MfaImage.isHidden = true;
            TimeoutImage.isHidden = true;
            
            if (self.timeLeft > 0) {
                self.timeLeft -= 1;
                let (h, m, s) = secondsToHoursMinutesSeconds(self.timeLeft);
                TimeoutImage.toolTip = ("\(h) Hours, \(m) Minutes, \(s) Seconds");
            } else {
                SetTimedOut();
            }
        } else {
            if (self.timeLeft > 0) {
                self.timeLeft -= 1;
            } else {
                SetTimedOut();
            }
        }
    }
    
    @IBAction func ShowDetails(_ sender: NSClickGestureRecognizer) {
        self.vc.ShowServiceDetails(service: self.service);
    }
    
    @IBAction func DoMfa(_ sender: NSClickGestureRecognizer) {
    }
    
}
