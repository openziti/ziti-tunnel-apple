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
    let XIB = "ServiceListItem";
    
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
        // Add Mfa posture check for showing which image
    }
    
    @IBAction func ShowDetails(_ sender: NSClickGestureRecognizer) {
    }
    
    @IBAction func DoMfa(_ sender: NSClickGestureRecognizer) {
    }
    
}
