//
//  TunnelSettingsViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/10/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import UIKit
import NetworkExtension

class TunnelSettingsViewController: UIViewController {
    weak var tvc:TableViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let protoConf = tvc?.tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = protoConf.providerConfiguration {
            if let ip = conf[ProviderConfig.IP_KEY] as? String,
                let mask = conf[ProviderConfig.SUBNET_KEY] as? String,
                let mtu = conf[ProviderConfig.MTU_KEY] as? String,
                let dns = conf[ProviderConfig.DNS_KEY] as? String
            {
                print("TODO: Tunnel Config = \(ip)/\(mask), mtu:\(mtu), dns:\(dns)")
            }
        }
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
