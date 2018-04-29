//
//  ViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa
import NetworkExtension

class ViewController: NSViewController {

    @IBOutlet weak var connectButton: NSButton!
    @IBOutlet weak var connectStatus: NSTextField!
    @IBOutlet weak var editBox: NSBox!
    @IBOutlet weak var ipAddressText: NSTextField!
    @IBOutlet weak var subnetMaskText: NSTextField!
    @IBOutlet weak var mtuText: NSTextField!
    @IBOutlet weak var dnsServersText: NSTextField!
    @IBOutlet weak var matchedDomainsText: NSTextField!
    
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
                // imported, but handy for development
                if self.tunnelProviderManager.protocolConfiguration == nil {
                    
                    let providerProtocol = NETunnelProviderProtocol()
                    
                    providerProtocol.providerBundleIdentifier = "com.ampifyllc.ZitiPacketTunnel.PacketTunnelProvider"
                    
                    
                    providerProtocol.providerConfiguration = ["ip": "169.254.126.1",
                                                              "subnet": "255.255.255.0",
                                                              "mtu": "2000",
                                                              "dns": "169.254.126.2",
                                                              "matchDomains": "",
                                                              "dnsProxies": "1.1.1.1,1.0.0.1"]
                    
                    providerProtocol.serverAddress = "169.254.126.255" // TODO
                    providerProtocol.username = "NetFoundry"
                    
                    self.tunnelProviderManager.protocolConfiguration = providerProtocol
                    self.tunnelProviderManager.localizedDescription = "Ziti Packet Tunnel"
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
        
        if self.tunnelProviderManager.protocolConfiguration == nil {
            return
        }
        
        let conf = (self.tunnelProviderManager.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as [String : AnyObject]

        if let ip = conf["ip"] {
            self.ipAddressText.stringValue = ip as! String
        }
        
        if let subnet = conf["subnet"] {
            self.subnetMaskText.stringValue = subnet as! String
        }
        
        if let mtu = conf["mtu"] {
            self.mtuText.stringValue = mtu as! String
        }
        
        if let dns = conf["dns"] {
            self.dnsServersText.stringValue = dns as! String
        }
        
        if let matchDomains = conf["matchDomains"] {
            self.matchedDomainsText.stringValue = matchDomains as! String
        } 
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

    @IBAction func onConnectButton(_ sender: NSButton) {
        print("onConnectButton")
        
        self.tunnelProviderManager.loadFromPreferences { (error:Error?) in
            if let error = error {
                print(error)
            }
            
            if (sender.title == "Turn Ziti On") {
                do {
                    try self.tunnelProviderManager.connection.startVPNTunnel()
                } catch {
                    print(error)
                }
            } else {
                self.tunnelProviderManager.connection.stopVPNTunnel()
            }
        }
    }
    

}

