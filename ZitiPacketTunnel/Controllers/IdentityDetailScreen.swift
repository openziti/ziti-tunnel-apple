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

class IdentityDetailScreen: NSViewController {
    
    var identity:ZitiIdentity?;
    var dash:DashboardScreen?;
    var enrollingIds:[ZitiIdentity] = [];
    var zidMgr:ZidMgr?;
    var tunnelMgr = TunnelMgr.shared;
    var heig = CGFloat(0.0);
    
    @IBOutlet var ToggleIdentity: NSSwitch!
    @IBOutlet var IdName: NSTextField!
    @IBOutlet var IdNetwork: NSTextField!
    @IBOutlet var IdEnrolled: NSTextField!
    @IBOutlet var IdStatus: NSTextField!
    @IBOutlet var IdServiceCount: NSTextField!
    @IBOutlet var CloseButton: NSImageView!
    @IBOutlet var EnrollButton: NSTextField!
    @IBOutlet var ServiceList: NSScrollView!
    @IBOutlet var ForgotButton: NSTextField!
    @IBOutlet var MFAOn: NSImageView!
    @IBOutlet var MFAOff: NSImageView!
    @IBOutlet var MFARecovery: NSImageView!
    @IBOutlet var MFAToggle: NSSwitch!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    override func viewDidLoad() {
        MFAToggle.layer?.backgroundColor = NSColor.red.cgColor;
        MFAToggle.layer?.masksToBounds = true;
        MFAToggle.layer?.cornerRadius = 10;
        SetupCursor();
        Setup();
    }
    
    @IBAction func Forget(_ sender: NSClickGestureRecognizer) {
        
        guard let zid = self.identity else { return };
        guard let zidMgr = self.zidMgr else { return };
        
        let text = "Deleting identity \(zid.name) (\(zid.id)) can't be undone"
        if dialogOKCancel(question: "Are you sure?", text: text) == true {
            let error = zidMgr.zidStore.remove(zid)
            guard error == nil else {
                dialogAlert("Unable to remove identity", error!.localizedDescription)
                return
            }
            
            // self.zidMgr.zids.remove(at: indx)
            dash?.UpdateList();
            dismiss(self);
            
        }
    }
    
    func Setup() {
        guard let zid = self.identity else { return };
        ToggleIdentity.isHidden = false;
        ForgotButton.isHidden = false;
        ServiceList.isHidden = false;
        IdServiceCount.isHidden = false;
        if (zid.isEnabled) {
            ToggleIdentity.state = .on;
        } else {
            ToggleIdentity.state = .off;
        }
        if (zid.isEnabled) {
            IdStatus.stringValue = "active";
        } else {
            IdStatus.stringValue = "inactive";
        }
        if (zid.isEnrolled) {
            IdEnrolled.stringValue = "enrolled";
        } else {
            IdEnrolled.stringValue = "not enrolled";
            ToggleIdentity.isHidden = true;
            ForgotButton.isHidden = true;
            ServiceList.isHidden = true;
            IdServiceCount.isHidden = true;
        }
        IdName.stringValue = zid.name;
        IdNetwork.stringValue = zid.czid?.ztAPI ?? "no network";
        IdServiceCount.stringValue = "\(zid.services.count) Services";
        
        MFAOn.isHidden = true; // Show is enabled and authenticated
        // MFAOff.isHidden = true; - show if enabled
        // MFARecovery.isHidden = true; - show if authenticated
        
            
        let serviceListView = NSStackView(frame: NSRect(x: 0, y: 0, width: self.view.frame.width-50, height: 70));
        serviceListView.orientation = .vertical;
        serviceListView.spacing = 2;
        var baseHeight = 480;
        var index = 0;
        
        if (zid.isEnrolled) {
            let rowHeight = 50;
            for service in zid.services {
                let serviceName = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 14));
                let serviceUrl = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 12));
                let serviceProtocol = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 12));
                let servicePorts = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 12));
                
                serviceName.string = service.name ?? "";
                serviceUrl.string = service.addresses ?? "None";
                serviceUrl.string = service.protocols ?? "None";
                serviceUrl.string = service.portRanges ?? "None";
                
                serviceName.font = NSFont(name: "Open Sans", size: 12);
                serviceName.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00);
                serviceUrl.font = NSFont(name: "Open Sans", size: 11);
                serviceUrl.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60);
                serviceProtocol.font = NSFont(name: "Open Sans", size: 11);
                serviceProtocol.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60);
                servicePorts.font = NSFont(name: "Open Sans", size: 11);
                servicePorts.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60);
                
                serviceName.isEditable = false;
                serviceUrl.isEditable = false;
                serviceProtocol.isEditable = false;
                servicePorts.isEditable = false;
                
                serviceName.backgroundColor = NSColor.clear;
                serviceUrl.backgroundColor = NSColor.clear;
                serviceProtocol.backgroundColor = NSColor.clear;
                servicePorts.backgroundColor = NSColor.clear;
                
                serviceName.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                serviceName.heightAnchor.constraint(equalToConstant: CGFloat(14)).isActive = true
                serviceUrl.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                serviceUrl.heightAnchor.constraint(equalToConstant: CGFloat(12)).isActive = true
                serviceProtocol.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                serviceProtocol.heightAnchor.constraint(equalToConstant: CGFloat(12)).isActive = true
                servicePorts.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                servicePorts.heightAnchor.constraint(equalToConstant: CGFloat(12)).isActive = true
                
                let stack = NSStackView(views: [serviceName, serviceUrl, serviceProtocol, servicePorts]);
                
                stack.edgeInsets.top = 14;
                stack.distribution = .fillProportionally;
                stack.alignment = .leading;
                stack.spacing = 0;
                stack.orientation = .vertical;
                stack.frame = CGRect(x: 0, y: CGFloat(index*rowHeight), width: view.frame.size.width-90, height: CGFloat(rowHeight));

                serviceListView.addSubview(stack);
                index = index + 1;
            }
            
            let clipView = FlippedClipView();
            clipView.drawsBackground = false;
            ServiceList.horizontalScrollElasticity = .none;
            ServiceList.contentView = clipView
            clipView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
              clipView.leftAnchor.constraint(equalTo: ServiceList.leftAnchor),
              clipView.rightAnchor.constraint(equalTo: ServiceList.rightAnchor),
              clipView.topAnchor.constraint(equalTo: ServiceList.topAnchor),
              clipView.bottomAnchor.constraint(equalTo: ServiceList.bottomAnchor)
            ]);
            
            serviceListView.frame = CGRect(x: 0, y: 0, width: view.frame.size.width-50, height: CGFloat(((rowHeight*index))));
            ServiceList.documentView = serviceListView;
            EnrollButton.isHidden = true;
        } else {
            EnrollButton.isHidden = false;
        }
        
        if (index>3) {
            index = index-2;
            baseHeight = baseHeight+(50*index);
        }
        guard var frame = self.view.window?.frame else { return };
        frame.size = NSMakeSize(CGFloat(420), CGFloat(baseHeight));
        self.view.window?.setFrame(frame, display: true);
        
        ServiceList.documentView = serviceListView;
    }
    
    @IBAction func AuthClicked(_ sender: NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let mfa = storyBoard.instantiateController(withIdentifier: "AuthenticateScreen") as! AuthenticateScreen;
        
        self.presentAsSheet(mfa);
    }
    
    override func viewWillLayout() {
        preferredContentSize = view.frame.size
    }
    
    @IBAction func ShowRecoveryScreen(_ sender: NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let mfa = storyBoard.instantiateController(withIdentifier: "RecoveryScreen") as! RecoveryScreen;
        
        self.presentAsSheet(mfa);
    }
    
    @IBAction func ToggleMFA(_ sender: NSClickGestureRecognizer) {
        if (MFAToggle.state == .off) {
            MFAToggle.state = .on;
            // prompty to setup MFA
            
            let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
            let mfa = storyBoard.instantiateController(withIdentifier: "MFASetupScreen") as! MFASetupScreen;
            
            // Send in the url and secret code to setup MFA
            
            self.presentAsSheet(mfa);
        } else {
            // prompt to turn off mfa if it is enabled
            MFAToggle.state = .off;
        }
    }
    
    @IBAction func Toggled(_ sender: NSClickGestureRecognizer) {
        guard let zid = self.identity else { return };
        guard let zidMgr = self.zidMgr else { return };
        zid.enabled = ToggleIdentity.state != .on;
        zidMgr.zidStore.store(zid);
        Setup();
        tunnelMgr.restartTunnel();
        self.dash?.UpdateList();
    }
    
    func dialogAlert(_ msg:String, _ text:String? = nil) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText =  text ?? ""
        alert.alertStyle = NSAlert.Style.critical
        alert.runModal()
    }
    
    func dialogOKCancel(question: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    @IBAction func Enroll(_ sender: Any) {
        EnrollButton.isHidden = true;
        guard let zid = self.identity else { return };
        guard let zidMgr = self.zidMgr else { return };
        enrollingIds.append(zid);
        // updateServiceUI(zId: zid)
        
        guard let presentedItemURL = zidMgr.zidStore.presentedItemURL else {
            self.dialogAlert("Unable to enroll \(zid.name)", "Unable to access group container");
            return;
        }
        
        let url = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false);
        let jwtFile = url.path;
        
        // Ziti.enroll takes too long, needs to be done in background
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async {
                    self.enrollingIds.removeAll { $0.id == zid.id }
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = zidMgr.zidStore.store(zid);
                        //self.updateServiceUI(zId:zid)
                        self.dialogAlert("Unable to enroll \(zid.name)", zErr != nil ? zErr!.localizedDescription : "invalid response");
                        return;
                    }
                    
                    if zid.czid == nil {
                        zid.czid = CZiti.ZitiIdentity(id: zidResp.id, ztAPI: zidResp.ztAPI);
                    }
                    zid.czid?.ca = zidResp.ca;
                    if zidResp.name != nil {
                        zid.czid?.name = zidResp.name;
                    }
                    
                    zid.enabled = true;
                    zid.enrolled = true;
                    _ = zidMgr.zidStore.store(zid);
                    //self.updateServiceUI(zId:zid)
                    self.tunnelMgr.restartTunnel();
                    self.Setup();
                }
            }
        }
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    func SetupCursor() {
        let items = [CloseButton, EnrollButton, ForgotButton, ToggleIdentity, MFAToggle, MFAOff, MFARecovery];
        
        pointingHand = NSCursor.pointingHand;
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        }

        arrow = NSCursor.arrow
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
        }
    }
    
}
