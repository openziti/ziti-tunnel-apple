//
//  ViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa
import NetworkExtension

class ViewController: NSViewController, NSTextFieldDelegate {

    @IBOutlet weak var connectButton: NSButton!
    @IBOutlet weak var connectStatus: NSTextField!
    @IBOutlet weak var editBox: NSBox!
    @IBOutlet weak var ipAddressText: NSTextField!
    @IBOutlet weak var subnetMaskText: NSTextField!
    @IBOutlet weak var mtuText: NSTextField!
    @IBOutlet weak var dnsServersText: NSTextField!
    @IBOutlet weak var matchedDomainsText: NSTextField!
    @IBOutlet weak var dnsProxiesText: NSTextField!
    @IBOutlet weak var revertButton: NSButton!
    @IBOutlet weak var applyButton: NSButton!
    
    var tunnelProviderManager: NETunnelProviderManager = NETunnelProviderManager()
    
    private func initTunnelProviderManager() {
        NETunnelProviderManager.loadAllFromPreferences { (savedManagers: [NETunnelProviderManager]?, error: Error?) in
            
            //
            // Find our manager (there should only be one, since we only are managing a single
            // extension).  If error and savedManagers are both nil that means there is no previous
            // configuration stored for this app (e.g., first time run, no Preference Profile loaded)
            // Note self.tunnelProviderManager will never be nil.
            //
            if let error = error {
                NSLog(error.localizedDescription)
                // keep going - we still might need to set default values...
            }
            
            if let savedManagers = savedManagers {
                if savedManagers.count > 0 {
                    self.tunnelProviderManager = savedManagers[0]
                }
            }
            
            self.tunnelProviderManager.loadFromPreferences(completionHandler: { (error:Error?) in
                
                if let error = error {
                    NSLog(error.localizedDescription)
                }
                
                // This shouldn't happen unless first time run and no profile preference has been
                // imported, but handy for development...
                if self.tunnelProviderManager.protocolConfiguration == nil {
                    
                    let providerProtocol = NETunnelProviderProtocol()
                    providerProtocol.providerBundleIdentifier = ProviderConfig.providerBundleIdentifier
                    
                    let defaultProviderConf = ProviderConfig()
                    providerProtocol.providerConfiguration = defaultProviderConf.createDictionary()
                    providerProtocol.serverAddress = defaultProviderConf.serverAddress
                    providerProtocol.username = defaultProviderConf.username
                    
                    self.tunnelProviderManager.protocolConfiguration = providerProtocol
                    self.tunnelProviderManager.localizedDescription = defaultProviderConf.localizedDescription
                    self.tunnelProviderManager.isEnabled = true
                    
                    self.tunnelProviderManager.saveToPreferences(completionHandler: { (error:Error?) in
                        if let error = error {
                            NSLog(error.localizedDescription)
                        } else {
                            print("Saved successfully")
                        }
                    })
                }
                
                self.updateConfigControls()
                
                // update the Connect Button label
                self.TunnelStatusDidChange(nil)
            })
        }
    }
    
    private func updateConfigControls() {
        
        self.ipAddressText.stringValue = ""
        self.subnetMaskText.stringValue = ""
        self.mtuText.stringValue = ""
        self.dnsServersText.stringValue = ""
        self.matchedDomainsText.stringValue = ""
        self.dnsProxiesText.stringValue = ""
        
        if self.tunnelProviderManager.protocolConfiguration == nil {
            return
        }
        
        let conf = (self.tunnelProviderManager.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as ProviderConfigDict

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
        
        if let dnsProxies = conf[ProviderConfig.DNS_PROXIES_KEY] {
            self.dnsProxiesText.stringValue = dnsProxies as! String
        }
        
        self.ipAddressText.becomeFirstResponder()
    }
    
    @objc func TunnelStatusDidChange(_ notification: Notification?) {
        print("Tunnel Status changed:")
        let status = self.tunnelProviderManager.connection.status
        switch status {
        case .connecting:
            print("Connecting...")
            connectStatus.stringValue = "Connecting..."
            connectButton.title = "Turn Ziti Off"
            break
        case .connected:
            print("Connected...")
            connectStatus.stringValue = "Connected"
            connectButton.title = "Turn Ziti Off"
            break
        case .disconnecting:
            print("Disconnecting...")
            connectStatus.stringValue = "Disconnecting..."
            break
        case .disconnected:
            print("Disconnected...")
            connectStatus.stringValue = "Disconnected"
            connectButton.title = "Turn Ziti On"
            break
        case .invalid:
            print("Invalid")
            break
        case .reasserting:
            print("Reasserting...")
            break
        }
    }
   
    override func viewDidLoad() {
        super.viewDidLoad()
        
        editBox.borderType = NSBorderType.lineBorder
        self.ipAddressText.delegate = self
        self.subnetMaskText.delegate = self
        self.mtuText.delegate = self
        self.dnsServersText.delegate = self
        self.matchedDomainsText.delegate = self
        self.dnsProxiesText.delegate = self

        initTunnelProviderManager()
        
        /* quick test...
        self.tunnelProviderManager.removeFromPreferences(completionHandler: { (error:Error?) in
            if let error = error {
                print(error)
            }
        })
         */
        
        NotificationCenter.default.addObserver(self, selector:
            #selector(ViewController.TunnelStatusDidChange(_:)), name:
            NSNotification.Name.NEVPNStatusDidChange, object: nil)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    // Occurs whenever you input first symbol after focus is here
    override func controlTextDidBeginEditing(_ obj: Notification) {
        self.revertButton.isEnabled = true
        self.applyButton.isEnabled = true
    }

    @IBAction func onApplyButton(_ sender: Any) {
        
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = self.ipAddressText.stringValue
        dict[ProviderConfig.SUBNET_KEY] = self.subnetMaskText.stringValue
        dict[ProviderConfig.MTU_KEY] = self.mtuText.stringValue
        dict[ProviderConfig.DNS_KEY] = self.dnsServersText.stringValue
        dict[ProviderConfig.MATCH_DOMAINS_KEY] = self.matchedDomainsText.stringValue
        dict[ProviderConfig.DNS_PROXIES_KEY] = self.dnsProxiesText.stringValue
        
        let conf:ProviderConfig = ProviderConfig()
        if let error = conf.parseDictionary(dict) {
            // TOOO alert and get outta here
            print("Error validating conf. \(error)")
            let alert = NSAlert()
            alert.messageText = "Configuration Error"
            alert.informativeText =  error.description
            alert.alertStyle = NSAlert.Style.critical
            alert.runModal()
            return
        }
        
        (self.tunnelProviderManager.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration = conf.createDictionary()
        self.tunnelProviderManager.saveToPreferences { error in
            if let error = error {
                print("Error saving perferences \(error)")
                NSAlert(error:error).runModal()
            }
        }
        
        // TODO: Either send message to the Provider letting it know config changed or, if tunnel is
        // running re-start it...?  Or do nothing...
        
/*        if let session = self.tunnelProviderManager.connection as? NETunnelProviderSession,
            let message = "Hello Provider".data(using: String.Encoding.utf8),
            self.tunnelProviderManager.connection.status != .invalid {
            
            do {
                try session.sendProviderMessage(message) { response in
                    if response != nil {
                        let responseString = NSString(data: response!, encoding: String.Encoding.utf8.rawValue)
                        print("Received response from the provider: \(responseString ?? "-no response-")")
                        let alert = NSAlert()
                        alert.messageText = "Ziti Packer Tunnel"
                        alert.informativeText = "Received response from the provider: \(responseString ?? "-no response-")"
                        alert.alertStyle = NSAlert.Style.informational
                        alert.runModal()
                    } else {
                        print("Got a nil response from the provider")
                    }
                }
            } catch {
                print("Failed to send a message to the provider")
            }
        }
 */
    }
    
    @IBAction func onRevertButton(_ sender: Any) {
        self.updateConfigControls()
        self.revertButton.isEnabled = false
        self.applyButton.isEnabled = false
    }
    
    @IBAction func onConnectButton(_ sender: NSButton) {
        print("onConnectButton")
        
        if (sender.title == "Turn Ziti On") {
            do {
                try self.tunnelProviderManager.connection.startVPNTunnel()
            } catch {
                print(error)
                NSAlert(error:error).runModal()
            }
        } else {
            self.tunnelProviderManager.connection.stopVPNTunnel()
        }
    }
}

