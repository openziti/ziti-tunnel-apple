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
import CZiti

class TunnelSettingsCell: UITableViewCell {
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var value: UITextField!
    
    var onChanged:((TunnelSettingsCell) -> Void)?
    @IBAction func editingChanged(_ sender: Any) {
        onChanged?(self)
    }
}

class TunnelSettingsViewController: UITableViewController {
    weak var tvc:TableViewController?
    var saveBtn:UIBarButtonItem?
    
    var ip:String = "0.0.0.0"
    var mask:String = "255.0.0.0"
    var mtu:String = "0"
    var dns:String = "0.0.0.0"
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let protoConf = tvc?.tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
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
        
        saveBtn = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(onSave))
        navigationItem.rightBarButtonItem = saveBtn
        saveBtn?.isEnabled = false
    }
    
    @objc func onSave() {
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = ip
        dict[ProviderConfig.SUBNET_KEY] = mask
        dict[ProviderConfig.MTU_KEY] = mtu
        dict[ProviderConfig.DNS_KEY] = dns
        dict[ProviderConfig.LOG_LEVEL] = String(ZitiLog.getLogLevel().rawValue)
        
        let conf:ProviderConfig = ProviderConfig()
        if let error = conf.parseDictionary(dict) {
            // alert and get outta here
            let alert = UIAlertController(
                title:"Configuration Error",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            tvc?.present(alert, animated: true, completion: nil)
            return
        }
        
        if let pc = tvc?.tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol {
            pc.providerConfiguration = conf.createDictionary()
            
            self.tvc?.tunnelMgr.tpm?.saveToPreferences { error in
                if let error = error {
                    let alert = UIAlertController(
                        title:"Configuation Save Error",
                        message: error.localizedDescription,
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                    self.tvc?.present(alert, animated: true, completion: nil)
                } else {
                    self.tvc?.tunnelMgr.restartTunnel()
                    self.navigationController?.popViewController(animated: true)
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var nRows = 1
        if section == 0 {
            nRows = 4
        } 
        return nRows
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell?
        
        // Configure the cell...
        //if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "TUNNEL_SETTING_CELL", for: indexPath)
            if let settingsCell = cell as? TunnelSettingsCell {
                if indexPath.row == 0 {
                    settingsCell.label.text = "IP Address"
                    settingsCell.value.text = ip
                    settingsCell.onChanged = { [weak self] sc in
                        self?.ip = sc.value.text ?? ""
                        self?.saveBtn?.isEnabled = self?.validate() ?? false
                    }
                    settingsCell.value.becomeFirstResponder()
                } else if indexPath.row == 1 {
                    settingsCell.label.text = "Subnet Mask"
                    settingsCell.value.text = mask
                    settingsCell.onChanged = { [weak self] sc in
                        self?.mask = sc.value.text ?? ""
                        self?.saveBtn?.isEnabled = self?.validate() ?? false
                    }
                } else if indexPath.row == 2 {
                    settingsCell.label.text = "MTU"
                    settingsCell.value.text = mtu
                    settingsCell.onChanged = { [weak self] sc in
                        self?.mtu = sc.value.text ?? ""
                        self?.saveBtn?.isEnabled = self?.validate() ?? false
                    }
                } else {
                    settingsCell.label.text = "DNS Server"
                    settingsCell.value.text = dns
                    settingsCell.onChanged = { [weak self] sc in
                        self?.dns = sc.value.text ?? ""
                        self?.saveBtn?.isEnabled = self?.validate() ?? false
                    }
                }
            }
        //}
        return cell! // Don't let this happen!
    }
}
