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
import NetworkExtension

extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

class ConfigScreen: NSViewController {
    
    @IBOutlet var BackButton: NSImageView!
    @IBOutlet var CloseButton: NSImageView!
    @IBOutlet var IPAddress: NSTextField!
    @IBOutlet var SubNet: NSTextField!
    @IBOutlet var MTU: NSTextField!
    @IBOutlet var DNS: NSTextField!
    @IBOutlet var Matched: NSTextField!
    @IBOutlet var SaveButton: NSTextField!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    var tunnelMgr = TunnelMgr.shared
    
    override func viewDidLoad() {
        SetupCursor();
        
        self.IPAddress.stringValue = "0.0.0.0"
        self.SubNet.stringValue = "0.0.0.0"
        self.MTU.stringValue = "0"
        self.DNS.stringValue = ""
        self.Matched.stringValue = ""
        
        guard
            let pp = tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = pp.providerConfiguration
        else { return }
        
        if let ip = conf[ProviderConfig.IP_KEY] {
            self.IPAddress.stringValue = ip as! String
        }
        
        if let subnet = conf[ProviderConfig.SUBNET_KEY] {
            self.SubNet.stringValue = subnet as! String
        }
        
        if let mtu = conf[ProviderConfig.MTU_KEY] {
            self.MTU.stringValue = mtu as! String
        }
        
        if let dns = conf[ProviderConfig.DNS_KEY] {
            self.DNS.stringValue = dns as! String
        }
        
        if let matchDomains = conf[ProviderConfig.MATCH_DOMAINS_KEY] {
            self.Matched.stringValue = matchDomains as! String
        }
        self.IPAddress.becomeFirstResponder()
    }
    
    @IBAction func SaveConfig(_ sender: Any) {
        
            var dict = ProviderConfigDict()
            dict[ProviderConfig.IP_KEY] = self.IPAddress.stringValue
            dict[ProviderConfig.SUBNET_KEY] = self.SubNet.stringValue
            dict[ProviderConfig.MTU_KEY] = self.MTU.stringValue
            dict[ProviderConfig.DNS_KEY] = self.DNS.stringValue
            dict[ProviderConfig.MATCH_DOMAINS_KEY] = self.Matched.stringValue
            dict[ProviderConfig.LOG_LEVEL] = String(ZitiLog.getLogLevel().rawValue)
            
            let conf:ProviderConfig = ProviderConfig()
            if let error = conf.parseDictionary(dict) {
                // alert and get outta here
                let alert = NSAlert()
                alert.messageText = "Configuration Error"
                alert.informativeText =  error.description
                alert.alertStyle = NSAlert.Style.critical
                alert.runModal()
                return
            }
            
        if let pc = self.tunnelMgr.tpm?.protocolConfiguration {
                (pc as! NETunnelProviderProtocol).providerConfiguration = conf.createDictionary()
                
                self.tunnelMgr.tpm?.saveToPreferences { error in
                    if let error = error {
                        NSAlert(error:error).runModal()
                    } else {
                        self.tunnelMgr.restartTunnel()
                        self.dismiss(self)
                    }
                }
            }
    }
    
    @IBAction func GoBack(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    func SetupCursor() {
        let items = [BackButton, CloseButton, SaveButton];
        
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
