//
// Copyright NetFoundry Inc.
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
    var restartRequired = false
    var requireRestart:[NSTextField] = []
    
    @IBOutlet weak var box: NSBox!
    @IBOutlet weak var ipAddressText: NSTextField!
    @IBOutlet weak var subnetMaskText: NSTextField!
    @IBOutlet weak var mtuText: NSTextField!
    @IBOutlet weak var dnsServersText: NSTextField!
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var fallbackDNSCheck: NSButton!
    @IBOutlet weak var fallbackDNSText: NSTextField!
    @IBOutlet weak var interceptMatchedDomainsSwitch: NSSwitch!
    @IBOutlet weak var lowPowerModeSwitch: NSSwitch!
    @IBOutlet weak var proxyModePopUp: NSPopUpButton!
    @IBOutlet weak var proxyHostText: NSTextField!
    @IBOutlet weak var proxyPortText: NSTextField!
    @IBOutlet weak var proxyUsernameText: NSTextField!
    @IBOutlet weak var proxyPasswordText: NSSecureTextField!
    @IBOutlet weak var proxyHostLabel: NSTextField!
    @IBOutlet weak var proxyPortLabel: NSTextField!
    @IBOutlet weak var proxyUsernameLabel: NSTextField!
    @IBOutlet weak var proxyPasswordLabel: NSTextField!

    // Track previous proxy host/port to clean up orphaned keychain credentials
    var previousProxyHost: String = ""
    var previousProxyPort: UInt16 = 0
    
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
        
        self.proxyHostText.delegate = self
        self.proxyPortText.delegate = self
        self.proxyUsernameText.delegate = self
        self.proxyPasswordText.delegate = self

        self.requireRestart = [ ipAddressText, subnetMaskText, dnsServersText, proxyHostText, proxyPortText ]

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
        self.lowPowerModeSwitch.state = defaults.lowPowerMode ? .on : .off
        self.proxyModePopUp.selectItem(at: 0)
        self.proxyHostText.stringValue = ""
        self.proxyPortText.stringValue = ""
        self.proxyUsernameText.stringValue = ""
        self.proxyPasswordText.stringValue = ""
        
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
        
        if let lowPowerMode = conf[ProviderConfig.LOW_POWER_MODE_KEY] as? Bool {
            self.lowPowerModeSwitch.state = lowPowerMode ? .on : .off
        }

        if let proxyMode = conf[ProviderConfig.PROXY_MODE_KEY] as? String {
            switch proxyMode {
            case "manual": self.proxyModePopUp.selectItem(at: 1)
            case "system": self.proxyModePopUp.selectItem(at: 2)
            default: self.proxyModePopUp.selectItem(at: 0)
            }
        }
        if let proxyHost = conf[ProviderConfig.PROXY_HOST_KEY] as? String {
            self.proxyHostText.stringValue = proxyHost
        }
        if let proxyPort = conf[ProviderConfig.PROXY_PORT_KEY] as? String {
            self.proxyPortText.stringValue = proxyPort
        }

        // Load credentials from keychain
        let credHost: String
        let credPort: UInt16
        if self.proxyModePopUp.indexOfSelectedItem == 2 {
            if let sp = ZitiHttpProxyConfig.systemProxy() {
                credHost = sp.host
                credPort = sp.port
            } else {
                credHost = ""
                credPort = 0
            }
        } else {
            credHost = self.proxyHostText.stringValue
            credPort = UInt16(self.proxyPortText.stringValue) ?? 0
        }
        if !credHost.isEmpty && credPort > 0 {
            if let creds = ZitiHttpProxyConfig.loadCredentials(proxyHost: credHost, proxyPort: credPort) {
                self.proxyUsernameText.stringValue = creds.username
                self.proxyPasswordText.stringValue = creds.password
            }
        }
        self.previousProxyHost = credHost
        self.previousProxyPort = credPort

        self.updateProxyFieldStates()

        self.ipAddressText.becomeFirstResponder()
    }
    
    // Occurs whenever you input first symbol after focus is here
    func controlTextDidBeginEditing(_ obj: Notification) {
        self.saveButton.isEnabled = true
        
        if let object = obj.object as? NSTextField, self.requireRestart.contains(object) {
            self.restartRequired = true
        }
    }
    
    @IBAction func onFallbackDNSCheck(_ sender: Any) {
        self.saveButton.isEnabled = true
        self.fallbackDNSText.isEnabled = self.fallbackDNSCheck.state == .on
    }
    
    @IBAction func onInterceptMatchedDomainsToggle(_ sender: Any) {
        self.saveButton.isEnabled = true
    }
    
    @IBAction func onLowPowerModeToggle(_ sender: Any) {
        self.saveButton.isEnabled = true
    }

    @IBAction func onProxyModeChanged(_ sender: Any) {
        self.saveButton.isEnabled = true
        self.restartRequired = true
        self.updateProxyFieldStates()
    }

    private func updateProxyFieldStates() {
        let mode = proxyModePopUp.indexOfSelectedItem  // 0=none, 1=manual, 2=system
        let isManual = (mode == 1)
        let hasProxy = (mode != 0)

        proxyHostText.isEnabled = isManual
        proxyPortText.isEnabled = isManual
        proxyHostLabel.textColor = isManual ? .labelColor : .disabledControlTextColor
        proxyPortLabel.textColor = isManual ? .labelColor : .disabledControlTextColor

        proxyUsernameText.isEnabled = hasProxy
        proxyPasswordText.isEnabled = hasProxy
        proxyUsernameLabel.textColor = hasProxy ? .labelColor : .disabledControlTextColor
        proxyPasswordLabel.textColor = hasProxy ? .labelColor : .disabledControlTextColor

        if mode == 2, let sp = ZitiHttpProxyConfig.systemProxy() {
            proxyHostText.stringValue = sp.host
            proxyPortText.stringValue = String(sp.port)
        } else if !isManual {
            proxyHostText.stringValue = ""
            proxyPortText.stringValue = ""
        }
        if !hasProxy {
            proxyUsernameText.stringValue = ""
            proxyPasswordText.stringValue = ""
        }
    }
    
    @IBAction func onSaveButton(_ sender: Any) {
        guard
            let pp = TunnelMgr.shared.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            var conf = pp.providerConfiguration else {
            zLog.error("Unable to access provider connfiguration")
            let alert = NSAlert()
            alert.messageText = "Access Error"
            alert.informativeText = "Unable to access provider configuration"
            alert.alertStyle = NSAlert.Style.critical
            alert.runModal()
            return
        }
        
        conf[ProviderConfig.IP_KEY] = self.ipAddressText.stringValue
        conf[ProviderConfig.SUBNET_KEY] = self.subnetMaskText.stringValue
        conf[ProviderConfig.MTU_KEY] = self.mtuText.stringValue
        conf[ProviderConfig.DNS_KEY] = self.dnsServersText.stringValue
        conf[ProviderConfig.FALLBACK_DNS_ENABLED_KEY] = self.fallbackDNSCheck.state == .on
        conf[ProviderConfig.FALLBACK_DNS_KEY] = self.fallbackDNSText.stringValue
        conf[ProviderConfig.INTERCEPT_MATCHED_DNS_KEY] = self.interceptMatchedDomainsSwitch.state == .on
        conf[ProviderConfig.LOW_POWER_MODE_KEY] = self.lowPowerModeSwitch.state == .on

        let proxyModeIndex = self.proxyModePopUp.indexOfSelectedItem
        let proxyMode: String
        switch proxyModeIndex {
        case 1: proxyMode = "manual"
        case 2: proxyMode = "system"
        default: proxyMode = "none"
        }
        conf[ProviderConfig.PROXY_MODE_KEY] = proxyMode
        conf[ProviderConfig.PROXY_HOST_KEY] = self.proxyHostText.stringValue
        conf[ProviderConfig.PROXY_PORT_KEY] = self.proxyPortText.stringValue

        // Validate before saving
        let pc = ProviderConfig()
        if let error = pc.validateDictionaty(conf) {
            let alert = NSAlert()
            alert.messageText = "Configuration Error"
            alert.informativeText = error.description
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        // Determine effective host/port for credential storage
        var effectiveHost = self.proxyHostText.stringValue
        var effectivePort = UInt16(self.proxyPortText.stringValue) ?? 0
        if proxyMode == "system" {
            if let sp = ZitiHttpProxyConfig.systemProxy() {
                effectiveHost = sp.host
                effectivePort = sp.port
            }
        }

        // Clean up old credentials if host/port changed
        if previousProxyHost != effectiveHost || previousProxyPort != effectivePort {
            if !previousProxyHost.isEmpty && previousProxyPort > 0 {
                ZitiHttpProxyConfig.deleteCredentials(proxyHost: previousProxyHost, proxyPort: previousProxyPort)
            }
        }

        // Store or delete credentials
        let username = self.proxyUsernameText.stringValue
        let password = self.proxyPasswordText.stringValue
        if proxyMode != "none" && !username.isEmpty && !password.isEmpty && !effectiveHost.isEmpty && effectivePort > 0 {
            if let err = ZitiHttpProxyConfig.storeCredentials(
                username: username, password: password,
                proxyHost: effectiveHost, proxyPort: effectivePort) {
                zLog.error("Failed to store proxy credentials: \(err.localizedDescription)")
            }
        } else if !effectiveHost.isEmpty && effectivePort > 0 {
            ZitiHttpProxyConfig.deleteCredentials(proxyHost: effectiveHost, proxyPort: effectivePort)
        }

        pp.providerConfiguration = conf
        TunnelMgr.shared.tpm?.saveToPreferences { error in
            if let error = error {
                NSAlert(error:error).runModal()
            } else {
                if self.restartRequired {
                    self.vc?.tunnelMgr.restartTunnel()
                } else {
                    self.vc?.tunnelMgr.reassert()
                }
                self.restartRequired = false
                self.saveButton.isEnabled = false
                self.dismiss(self)
                
                DispatchQueue.main.async {
                    guard let indx = self.vc?.representedObject as? Int else { return }
                    self.vc?.updateServiceUI(zId: self.vc?.zids[indx])
                }
            }
        }
    }
    
    @IBAction func onCancelButton(_ sender: Any) {
        self.dismiss(self)
    }
}
