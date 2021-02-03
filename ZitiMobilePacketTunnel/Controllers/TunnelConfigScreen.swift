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

import UIKit
import NetworkExtension


class TunnelConfigScreen: UIViewController, UIActivityItemSource {
    
    var ip:String = "0.0.0.0"
    var mask:String = "255.0.0.0"
    var mtu:String = "0"
    var dns:String = "0.0.0.0"
    
    @IBOutlet weak var IPAddress: UITextField!
    @IBOutlet weak var Mask: UITextField!
    @IBOutlet weak var MTU: UITextField!
    @IBOutlet weak var Dns: UITextField!
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet var SaveButton: NSTextField!
    
    var tunnelMgr = TunnelMgr.shared
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let protoConf = tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = protoConf.providerConfiguration {
            if let ip = conf[ProviderConfig.IP_KEY] as? String,
                let mask = conf[ProviderConfig.SUBNET_KEY] as? String,
                let mtu = conf[ProviderConfig.MTU_KEY] as? String,
                let dns = conf[ProviderConfig.DNS_KEY] as? String
            {
                self.ip = ip
                self.mask = mask
                self.mtu = mtu
                self.dns = dns
            }
        }
        
        saveButton?.isHidden = false
    }
    
    @IBAction func DNSChanged(_ sender: Any) {
        self.dns = Dns.text ?? "";
        self.saveButton.isHidden = !self.validate();
    }
    
    @IBAction func MTUChanged(_ sender: Any) {
        self.mtu = MTU.text ?? "";
        self.saveButton.isHidden = !self.validate();
    }
    
    @IBAction func MaskChanged(_ sender: Any) {
        self.mask = Mask.text ?? "";
        self.saveButton.isHidden = !self.validate();
    }
    
    @IBAction func IPChanged(_ sender: Any) {
        self.ip = IPAddress.text ?? "";
        self.saveButton.isHidden = !self.validate();
    }
    
    @IBAction func dismissVC(_ sender: Any) {
         dismiss(animated: true, completion: nil)
    }
    
    @IBAction func SaveConfig(_ sender: UIButton) {
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = ip
        dict[ProviderConfig.SUBNET_KEY] = mask
        dict[ProviderConfig.MTU_KEY] = mtu
        dict[ProviderConfig.DNS_KEY] = dns
        
        let conf:ProviderConfig = ProviderConfig()
        if let error = conf.parseDictionary(dict) {
            // alert and get outta here
            let alert = UIAlertController(
                title:"Configuration Error",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        if let pc = tunnelMgr.tpm?.protocolConfiguration {
            (pc as! NETunnelProviderProtocol).providerConfiguration = conf.createDictionary()
            
            self.tunnelMgr.tpm?.saveToPreferences { error in
                if let error = error {
                    let alert = UIAlertController(
                        title:"Configuation Save Error",
                        message: error.localizedDescription,
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                    self.present(alert, animated: true, completion: nil)
                } else {
                    self.tunnelMgr.restartTunnel()
                    self.dismiss(animated: true, completion: nil)
                }
            }
        }
    }
    
    func validate() -> Bool {
        guard IPUtils.isValidIpV4Address(ip) else { return false }
        guard IPUtils.isValidIpV4Address(mask) else { return false }
        guard Int(mtu) != nil else { return false }
        
        let dnsArray = dns.components(separatedBy: ",")
        guard dnsArray.count > 0 else {return false }
        return (dnsArray.contains { !IPUtils.isValidIpV4Address($0) }) == false
    }
    
    
}
