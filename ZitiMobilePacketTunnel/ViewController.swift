//
//  ViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 5/3/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import UIKit
import NetworkExtension

class ViewController: UIViewController {
    @IBOutlet weak var connectStatus: UILabel!
    @IBOutlet weak var connectSwitch: UISwitch!
    
    static let providerBundleIdentifier = "com.ampifyllc.ZitiMobilePacketTunnel.MobilePacketTunnelProvider"
    
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
                    providerProtocol.providerBundleIdentifier = ViewController.providerBundleIdentifier
                    
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
                self.tunnelStatusDidChange(nil)
            })
        }
    }
    
    private func updateConfigControls() {
        
    }
    
    @objc func tunnelStatusDidChange(_ notification: Notification?) {
        print("Tunnel Status changed:")
        let status = self.tunnelProviderManager.connection.status
        switch status {
        case .connecting:
            print("Connecting...")
            connectStatus.text = "Connecting..."
            break
        case .connected:
            print("Connected...")
            connectStatus.text = "Connected"
            connectSwitch.isOn = true
            break
        case .disconnecting:
            print("Disconnecting...")
            connectStatus.text = "Disconnecting..."
            break
        case .disconnected:
            print("Disconnected...")
            connectStatus.text = "Disconnected"
            connectSwitch.isOn = false
            break
        case .invalid:
            print("Invalid")
            connectSwitch.isOn = false
            break
        case .reasserting:
            print("Reasserting...")
            break
        }
    }
    
    @IBAction func connectSwitchChanged(_ sender: Any) {
        print("Connect switch: \(connectSwitch.isOn)")
        /*
        if !connectSwitch.isOn {
            do {
                try self.tunnelProviderManager.connection.startVPNTunnel()
            } catch {
                print(error)
                //NSAlert(error:error).runModal()
                let alert = UIAlertController(
                    title:"Ziti PT Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                self.present(alert, animated: true, completion: nil)

            }
        } else {
            self.tunnelProviderManager.connection.stopVPNTunnel()
        }
 */
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        initTunnelProviderManager()
        
        NotificationCenter.default.addObserver(self, selector:
            #selector(ViewController.tunnelStatusDidChange(_:)), name:
            NSNotification.Name.NEVPNStatusDidChange, object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

