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
import NetworkExtension
import CZiti

class TunnelConfigViewController: NSViewController, NSTextFieldDelegate {
    weak var vc: ViewController?
    
    @IBOutlet weak var box: NSBox!
    @IBOutlet weak var ipAddressText: NSTextField!
    @IBOutlet weak var subnetMaskText: NSTextField!
    @IBOutlet weak var mtuText: NSTextField!
    @IBOutlet weak var dnsServersText: NSTextField!
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var fallbackDNSCheck: NSButton!
    @IBOutlet weak var fallbackDNSText: NSTextField!
    @IBOutlet weak var interceptMatchedDomainsSwitch: NSSwitch!
    @IBOutlet weak var enableMfaSwitch: NSSwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        box.boxType = .custom
        box.fillColor = .underPageBackgroundColor
        box.isTransparent = false
        
        self.ipAddressText.delegate = self
        self.subnetMaskText.delegate = self
        self.mtuText.delegate = self
        self.dnsServersText.delegate = self
        self.fallbackDNSText.delegate = self
        
        self.updateConfigControls()
    }
    
    private func updateConfigControls() {
        
        let defaults = ProviderConfig()
        self.ipAddressText.stringValue = defaults.ipAddress
        self.subnetMaskText.stringValue = defaults.subnetMask
        self.mtuText.stringValue = String(defaults.mtu)
        self.dnsServersText.stringValue = defaults.dnsAddresses.joined(separator: ",")
        self.fallbackDNSCheck.state = defaults.fallbackDnsEnabled ? .on : .off
        self.fallbackDNSText.stringValue = defaults.fallbackDns
        self.interceptMatchedDomainsSwitch.state = defaults.interceptMatchedDns ? .on : .off
        self.enableMfaSwitch.state = defaults.enableMfa ? .on : .off
        
        guard
            let pp = vc?.tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = pp.providerConfiguration
        else { return }
        
        if let ip = conf[ProviderConfig.IP_KEY] as? String {
            self.ipAddressText.stringValue = ip
        }
        
        if let subnet = conf[ProviderConfig.SUBNET_KEY] as? String {
            self.subnetMaskText.stringValue = subnet
        }
        
        if let mtu = conf[ProviderConfig.MTU_KEY] as? String {
            self.mtuText.stringValue = mtu
        }
        
        if let dns = conf[ProviderConfig.DNS_KEY] as? String {
            self.dnsServersText.stringValue = dns
        }
        
        if let fallbackDnsEnbled = conf[ProviderConfig.FALLBACK_DNS_ENABLED_KEY] as? Bool {
            self.fallbackDNSCheck.state = fallbackDnsEnbled ? .on : .off
        }
        
        if let fallbackDns = conf[ProviderConfig.FALLBACK_DNS_KEY] as? String {
            self.fallbackDNSText.stringValue = fallbackDns
        }
        
        if let interceptMatchedDomains = conf[ProviderConfig.INTERCEPT_MATCHED_DNS_KEY] as? Bool {
            self.interceptMatchedDomainsSwitch.state = interceptMatchedDomains ? .on : .off
        }
        
        if let enableMfa = conf[ProviderConfig.ENABLE_MFA_KEY] as? Bool {
            self.enableMfaSwitch.state = enableMfa ? .on : .off
        }
        self.ipAddressText.becomeFirstResponder()
    }
    
    func configCheck(_ enabledSwitch:NSSwitch, _ toDisableSwitch:NSSwitch, _ text:String) {
        if enabledSwitch.state == .on && toDisableSwitch.state == .on {
            let alert = NSAlert()
            alert.messageText = "Configuration Notice"
            alert.informativeText = text
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { // OK
                toDisableSwitch.state = .off
            } else { // Cancel
                enabledSwitch.state = .off
            }
        }
    }
        
    // Occurs whenever you input first symbol after focus is here
    func controlTextDidBeginEditing(_ obj: Notification) {
        self.saveButton.isEnabled = true
    }
    
    @IBAction func onFallbackDNSCheck(_ sender: Any) {
        self.saveButton.isEnabled = true
        self.fallbackDNSText.isEnabled = self.fallbackDNSCheck.state == .on
    }
    
    @IBAction func onInterceptMatchedDomainsToggle(_ sender: Any) {
        self.saveButton.isEnabled = true
        configCheck(interceptMatchedDomainsSwitch, enableMfaSwitch,
                    "Enabling this mode requires MFA to be disabled.  Disable MFA and continue?")
    }
    
    @IBAction func onEnableMfaToggle(_ sender: Any) {
        self.saveButton.isEnabled = true
        configCheck(enableMfaSwitch, interceptMatchedDomainsSwitch,
                    "Enabling MFA requires intercepting by matching domains to be diabled. Disable and continue?")
    }
    
    @IBAction func onSaveButton(_ sender: Any) {
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = self.ipAddressText.stringValue
        dict[ProviderConfig.SUBNET_KEY] = self.subnetMaskText.stringValue
        dict[ProviderConfig.MTU_KEY] = self.mtuText.stringValue
        dict[ProviderConfig.DNS_KEY] = self.dnsServersText.stringValue
        dict[ProviderConfig.FALLBACK_DNS_ENABLED_KEY] = self.fallbackDNSCheck.state == .on
        dict[ProviderConfig.FALLBACK_DNS_KEY] = self.fallbackDNSText.stringValue
        dict[ProviderConfig.INTERCEPT_MATCHED_DNS_KEY] = self.interceptMatchedDomainsSwitch.state == .on
        dict[ProviderConfig.ENABLE_MFA_KEY] = self.enableMfaSwitch.state == .on
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
        
        if let pc = self.vc?.tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol {
            pc.providerConfiguration = conf.createDictionary()
            
            self.vc?.tunnelMgr.tpm?.saveToPreferences { error in
                if let error = error {
                    NSAlert(error:error).runModal()
                } else {
                    self.vc?.tunnelMgr.restartTunnel()
                    self.saveButton.isEnabled = false
                    self.dismiss(self)
                    
                    DispatchQueue.main.async {
                        guard let indx = self.vc?.representedObject as? Int else { return }
                        self.vc?.updateServiceUI(zId: self.vc?.zids[indx])
                    }
                }
            }
        }
    }
    
    @IBAction func onCancelButton(_ sender: Any) {
        self.dismiss(self)
    }
}
