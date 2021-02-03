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
    var zidMgr = ZidMgr();
    var tunnelMgr = TunnelMgr.shared;
    
    @IBOutlet var ToggleIdentity: NSSwitch!
    @IBOutlet var IdName: NSTextField!
    @IBOutlet var IdNetwork: NSTextField!
    @IBOutlet var IdEnrolled: NSTextField!
    @IBOutlet var IdStatus: NSTextField!
    @IBOutlet var IdServiceCount: NSTextField!
    @IBOutlet var CloseButton: NSImageView!
    @IBOutlet var EnrollButton: NSTextField!
    @IBOutlet var ServiceList: NSScrollView!
    
    override func viewDidLoad() {
        Setup();
    }
    
    func Setup() {
        guard let zid = self.identity else { return };
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
        }
        IdName.stringValue = zid.name;
        IdNetwork.stringValue = zid.czid?.ztAPI ?? "no network";
        IdServiceCount.stringValue = "\(zid.services.count) Services";
        
            
        let serviceListView = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 70));
        serviceListView.orientation = .vertical;
        
        if (zid.isEnrolled) {
            var index = 0;
            let rowHeight = 30;
            for service in zid.services {
                let serviceName = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 20));
                let serviceUrl = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 20));
                
                serviceName.string = service.name ?? "";
                serviceUrl.string = "\(service.dns?.hostname ?? ""):\(service.dns?.port ?? -1)";
                
                serviceName.font = NSFont(name: "Open Sans", size: 12);
                serviceName.textColor = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00);
                serviceUrl.font = NSFont(name: "Open Sans", size: 11);
                serviceUrl.textColor = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.80);
                
                serviceName.isEditable = false;
                //serviceName.isScrollEnabled = false;
                serviceUrl.isEditable = false;
                //serviceUrl.isScrollEnabled = false;
                //serviceUrl.textAlignment = .right;
                
                serviceName.backgroundColor = NSColor.clear;
                serviceUrl.backgroundColor = NSColor.clear;
                
                serviceName.widthAnchor.constraint(equalToConstant: self.view.frame.width).isActive = true
                serviceName.heightAnchor.constraint(equalToConstant: CGFloat(rowHeight)).isActive = true
                serviceUrl.widthAnchor.constraint(equalToConstant: self.view.frame.width).isActive = true
                serviceUrl.heightAnchor.constraint(equalToConstant: CGFloat(rowHeight)).isActive = true
                
                let stack = NSStackView(views: [serviceName, serviceUrl]);
                
                stack.distribution = .fill;
                stack.alignment = .leading;
                stack.spacing = 5;
                stack.orientation = .horizontal;
                stack.frame = CGRect(x: 20, y: CGFloat(index*rowHeight), width: view.frame.size.width-CGFloat(rowHeight), height: 30);

                serviceListView.addSubview(stack);
                index = index + 1;
            }
            //ServiceList.contentSize.height = CGFloat(index*rowHeight);
            EnrollButton.isHidden = true;
        } else {
            EnrollButton.isHidden = false;
        }
        ServiceList.documentView = serviceListView;
    }
    
    func dialogAlert(_ msg:String, _ text:String? = nil) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText =  text ?? ""
        alert.alertStyle = NSAlert.Style.critical
        alert.runModal()
    }
    
    @IBAction func Enroll(_ sender: Any) {
        EnrollButton.isHidden = true;
        guard let zid = self.identity else { return };
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
                        _ = self.zidMgr.zidStore.store(zid);
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
                    _ = self.zidMgr.zidStore.store(zid);
                    //self.updateServiceUI(zId:zid)
                    self.tunnelMgr.restartTunnel();
                }
            }
        }
    }
    
    @IBAction func Forget(_ sender: NSTextField) {

    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
}
