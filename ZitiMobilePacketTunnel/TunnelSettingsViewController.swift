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

protocol CellResettable {
    func reset()
}
class LowPowerModeCell: UITableViewCell, CellResettable {
    weak var tsvc:TunnelSettingsViewController?
    var origValue = false
    var requiresRestart = false
    
    @IBOutlet weak var lowPowerSwitch: UISwitch!
    
    var onChanged:((Bool) -> Void)?
    @IBAction func switchChanged(_ sender: Any) {
        if requiresRestart { tsvc?.restartRequired = true }
        tsvc?.resetBtn?.isEnabled = true
        onChanged?(lowPowerSwitch.isOn)
    }
    
    func setup(_ tsvc:TunnelSettingsViewController, _ value:Bool, _ requiresRestart:Bool, _ onChanged: @escaping (Bool)->Void) {
        self.tsvc = tsvc
        self.lowPowerSwitch.isOn = value
        self.origValue = value
        self.requiresRestart = requiresRestart
        self.onChanged = onChanged
    }
    
    func reset() {
        lowPowerSwitch.isOn = origValue
    }
}

class TunnelSettingsCell: UITableViewCell, CellResettable {
    weak var tsvc:TunnelSettingsViewController?
    var origValue:String?
    var requiresRestart = false
    
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var value: UITextField!
    
    var onChanged:((String) -> Void)?
    @IBAction func editingChanged(_ sender: Any) {
        if requiresRestart { tsvc?.restartRequired = true }
        tsvc?.resetBtn?.isEnabled = true
        onChanged?(value.text ?? "")
    }
    
    func setup(_ tsvc:TunnelSettingsViewController, _ label:String, _ value:String, _ requiresRestart:Bool, _ onChanged: @escaping (String)->Void) {
        self.tsvc = tsvc
        self.label.text = label
        self.origValue = value
        self.value.text = value
        self.requiresRestart = requiresRestart
        self.onChanged = onChanged
    }
    
    func reset() {
        self.value.text = self.origValue
    }
}

class TunnelSettingsViewController: UITableViewController {
    weak var tvc:TableViewController?
    var resetBtn:UIBarButtonItem?
    var restartRequired = false
    
    let defaults = ProviderConfig()
    
    var ip:String = "0.0.0.0"
    var mask:String = "255.0.0.0"
    var mtu:String = "0"
    var dns:String = "0.0.0.0"
    var lowPowerMode = true
    var tlsuvLoggingEnabled = false
    
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
                self.lowPowerMode = conf[ProviderConfig.LOW_POWER_MODE_KEY] as? Bool ?? defaults.lowPowerMode
                self.tlsuvLoggingEnabled = conf[ProviderConfig.LOG_TLSUV_KEY] as? Bool ?? defaults.logTlsuv
            }
        }
        
        resetBtn = UIBarButtonItem(title: "Reset", style: .done, target: self, action: #selector(onReset))
        navigationItem.rightBarButtonItem = resetBtn
        resetBtn?.isEnabled = false
    }
    
    @objc func onReset() {
        for c in tableView.visibleCells {
            if let rc = c as? CellResettable {
                rc.reset()
            }
        }
    }
    
    @objc func saveConfig() {
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = ip
        dict[ProviderConfig.SUBNET_KEY] = mask
        dict[ProviderConfig.MTU_KEY] = mtu
        dict[ProviderConfig.DNS_KEY] = dns
        dict[ProviderConfig.LOG_LEVEL_KEY] = String(ZitiLog.getLogLevel().rawValue)
        dict[ProviderConfig.LOG_TLSUV_KEY] = Bool(tlsuvLoggingEnabled)
        dict[ProviderConfig.LOW_POWER_MODE_KEY] = lowPowerMode
        
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
                    if self.restartRequired {
                        self.tvc?.tunnelMgr.restartTunnel()
                    } else {
                        self.tvc?.tunnelMgr.reassert()
                    }
                    //self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }
    
    // TODO: never gets called...
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // if nothing changed, we're done
        if !(resetBtn?.isEnabled ?? false) {
            return
        }
        
        if validate() == false {
            let alert = UIAlertController(
                title:"Configuration Error",
                message: "Invalid configuration settings, configuration will not be stored",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            tvc?.present(alert, animated: true, completion: nil)
            return
        }
        saveConfig()
    }
    
//    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
//        // Is this the base place to do this, or should it be done on viewWillDisappear? Problem with doing it there is we can't cancel it
//        // if the inputs are invalid. Downside of doing it here is if user edits and then leaves the app the changes won't take effect.  Downside
//        // of an explit Save button is that users hit Back expecting the changes have taken effect (especially the lowPowerMode toggle)
//        var performSegue = true
//        if resetBtn?.isEnabled ?? false {
//            performSegue =  onSave()
//        }
//        return performSegue
//    }
    
    func validate() -> Bool {
        guard IPUtils.isValidIpV4Address(ip) else { return false }
        guard IPUtils.isValidIpV4Address(mask) else { return false }
        guard Int(mtu) != nil else { return false }
        
        let dnsArray = dns.components(separatedBy: ",")
        guard dnsArray.count > 0 else {return false }
        return (dnsArray.contains { !IPUtils.isValidIpV4Address($0) }) == false
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1 // 2 setting to 1 effectively disables lowPowerMode...
        // TODO: lowPowerMode.  When re-enabled, also fix the logic that applies the settings (imm apply lowPowerMode, change Reset back to Save for others...)
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
        if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "TUNNEL_SETTING_CELL", for: indexPath)
            if let settingsCell = cell as? TunnelSettingsCell {
                if indexPath.row == 0 {
                    settingsCell.setup(self, "IP Address", ip, true) { [weak self] value in
                        self?.ip = value
                    }
                    settingsCell.value.becomeFirstResponder()
                } else if indexPath.row == 1 {
                    settingsCell.setup(self, "Subnet Mask", mask, true) { [weak self] value in
                        self?.mask = value
                    }
                } else if indexPath.row == 2 {
                    settingsCell.setup(self, "MTU", mtu, false) { [weak self] value in
                        self?.mtu = value
                    }
                } else {
                    settingsCell.setup(self, "DNS Server", dns, true) { [weak self] value in
                        self?.dns = value
                    }
                }
            }
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "LOW_POWER_MODE_CELL", for: indexPath)
            if let lowPowerCell = cell as? LowPowerModeCell {
                lowPowerCell.setup(self, lowPowerMode, false) { [weak self] value in
                    self?.lowPowerMode = value
                }
            }
        }
        return cell! // Don't let this happen!
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 {
            return "Disable all Ziti communications and traffic targeted for the tunnel (including DNS) when device not in use"
        }
        return nil
    }
}
