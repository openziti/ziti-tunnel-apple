//
//  TunnelConfigViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/19/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Cocoa
import NetworkExtension

class TunnelConfigViewController: NSViewController, NSTextFieldDelegate {
    weak var vc: ViewController?
    
    @IBOutlet weak var box: NSBox!
    @IBOutlet weak var ipAddressText: NSTextField!
    @IBOutlet weak var subnetMaskText: NSTextField!
    @IBOutlet weak var mtuText: NSTextField!
    @IBOutlet weak var dnsServersText: NSTextField!
    @IBOutlet weak var matchedDomainsText: NSTextField!
    @IBOutlet weak var saveButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        box.borderType = NSBorderType.lineBorder
        self.ipAddressText.delegate = self
        self.subnetMaskText.delegate = self
        self.mtuText.delegate = self
        self.dnsServersText.delegate = self
        self.matchedDomainsText.delegate = self
        
        self.updateConfigControls()
    }
    
    private func updateConfigControls() {
        self.ipAddressText.stringValue = ""
        self.subnetMaskText.stringValue = ""
        self.mtuText.stringValue = ""
        self.dnsServersText.stringValue = ""
        self.matchedDomainsText.stringValue = ""
        
        guard
            let pp = vc?.tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = pp.providerConfiguration
        else { return }
        
        if let ip = conf[ProviderConfig.IP_KEY] {
            self.ipAddressText.stringValue = ip as! String
        }
        
        if let subnet = conf[ProviderConfig.SUBNET_KEY] {
            self.subnetMaskText.stringValue = subnet as! String
        }
        
        if let mtu = conf[ProviderConfig.MTU_KEY] {
            self.mtuText.stringValue = mtu as! String
        }
        
        if let dns = conf[ProviderConfig.DNS_KEY] {
            self.dnsServersText.stringValue = dns as! String
        }
        
        if let matchDomains = conf[ProviderConfig.MATCH_DOMAINS_KEY] {
            self.matchedDomainsText.stringValue = matchDomains as! String
        }
        self.ipAddressText.becomeFirstResponder()
    }
        
    // Occurs whenever you input first symbol after focus is here
    func controlTextDidBeginEditing(_ obj: Notification) {
        self.saveButton.isEnabled = true
    }
    
    @IBAction func onSaveButton(_ sender: Any) {
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = self.ipAddressText.stringValue
        dict[ProviderConfig.SUBNET_KEY] = self.subnetMaskText.stringValue
        dict[ProviderConfig.MTU_KEY] = self.mtuText.stringValue
        dict[ProviderConfig.DNS_KEY] = self.dnsServersText.stringValue
        dict[ProviderConfig.MATCH_DOMAINS_KEY] = self.matchedDomainsText.stringValue
        
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
        
        if let pc = self.vc?.tunnelMgr.tpm?.protocolConfiguration {
            (pc as! NETunnelProviderProtocol).providerConfiguration = conf.createDictionary()
            
            self.vc?.tunnelMgr.tpm?.saveToPreferences { error in
                if let error = error {
                    NSAlert(error:error).runModal()
                } else {
                    self.vc?.tunnelMgr.restartTunnel()
                    self.saveButton.isEnabled = false
                    self.dismiss(self)
                }
            }
        }
    }
    
    @IBAction func onCancelButton(_ sender: Any) {
        self.dismiss(self)
    }
}
