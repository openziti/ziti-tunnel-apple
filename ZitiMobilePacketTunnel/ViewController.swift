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
    
    var tunnelProviderManager = NETunnelProviderManager()
    
    @objc func tunnelStatusDidChange(_ notification: Notification?) {
        let status = self.tunnelProviderManager.connection.status
        switch status {
        case .connecting:
            connectStatus.text = "Connecting..."
            break
        case .connected:
            connectStatus.text = "Connected"
            connectSwitch.isOn = true
            break
        case .disconnecting:
            connectStatus.text = "Disconnecting..."
            break
        case .disconnected:
            connectStatus.text = "Disconnected"
            connectSwitch.isOn = false
            break
        case .invalid:
            connectSwitch.isOn = false
            break
        case .reasserting:
            break
        @unknown default:
            connectStatus.text = "Unknown"
            connectSwitch.isOn = false
        }
    }
    
    @IBAction func connectSwitchChanged(_ sender: Any) {
        print("Connect switch: \(connectSwitch.isOn)")
        
        if connectSwitch.isOn {
            do {
                try self.tunnelProviderManager.connection.startVPNTunnel()
            } catch {
                print(error)
                let alert = UIAlertController(
                    title:"Ziti PT Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                self.present(alert, animated: true, completion: nil)
            }
        } else {
            self.tunnelProviderManager.connection.stopVPNTunnel()
        }
 
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // init the manager
        ProviderConfig.loadFromPreferences(ViewController.providerBundleIdentifier) { tpm, error in
            DispatchQueue.main.async {
                self.tunnelProviderManager = tpm
                self.tunnelStatusDidChange(nil)
            }
        }
        
        NotificationCenter.default.addObserver(self, selector:
            #selector(ViewController.tunnelStatusDidChange(_:)), name:
            NSNotification.Name.NEVPNStatusDidChange, object: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

