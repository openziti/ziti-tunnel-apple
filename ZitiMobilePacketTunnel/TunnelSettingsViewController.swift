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

class ProxyModeCell: UITableViewCell, CellResettable {
    weak var tsvc: TunnelSettingsViewController?
    var origIndex = 0

    let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["No Proxy", "Manual", "System"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    var onChanged: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            segmentedControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func segmentChanged() {
        tsvc?.restartRequired = true
        tsvc?.resetBtn?.isEnabled = true
        onChanged?(segmentedControl.selectedSegmentIndex)
    }

    func setup(_ tsvc: TunnelSettingsViewController, _ index: Int, _ onChanged: @escaping (Int) -> Void) {
        self.tsvc = tsvc
        self.segmentedControl.selectedSegmentIndex = index
        self.origIndex = index
        self.onChanged = onChanged
    }

    func reset() {
        segmentedControl.selectedSegmentIndex = origIndex
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

    var proxyModeIndex = 0  // 0=none, 1=manual, 2=system
    var proxyHost = ""
    var proxyPort = ""
    var proxyUsername = ""
    var proxyPassword = ""
    var previousProxyHost = ""
    var previousProxyPort: UInt16 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(ProxyModeCell.self, forCellReuseIdentifier: "PROXY_MODE_CELL")

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
            }

            // Load proxy settings
            if let proxyMode = conf[ProviderConfig.PROXY_MODE_KEY] as? String {
                switch proxyMode {
                case "manual": self.proxyModeIndex = 1
                case "system": self.proxyModeIndex = 2
                default: self.proxyModeIndex = 0
                }
            }
            if let proxyHost = conf[ProviderConfig.PROXY_HOST_KEY] as? String {
                self.proxyHost = proxyHost
            }
            if let proxyPort = conf[ProviderConfig.PROXY_PORT_KEY] as? String {
                self.proxyPort = proxyPort
            }

            // Populate system proxy host/port if in system mode
            if self.proxyModeIndex == 2, let sp = ZitiHttpProxyConfig.systemProxy() {
                self.proxyHost = sp.host
                self.proxyPort = String(sp.port)
            }

            // Load credentials from keychain
            let credHost: String
            let credPort: UInt16
            if self.proxyModeIndex == 2 {
                if let sp = ZitiHttpProxyConfig.systemProxy() {
                    credHost = sp.host
                    credPort = sp.port
                } else {
                    credHost = ""
                    credPort = 0
                }
            } else {
                credHost = self.proxyHost
                credPort = UInt16(self.proxyPort) ?? 0
            }
            if !credHost.isEmpty && credPort > 0 {
                if let creds = ZitiHttpProxyConfig.loadCredentials(proxyHost: credHost, proxyPort: credPort) {
                    self.proxyUsername = creds.username
                    self.proxyPassword = creds.password
                }
            }
            self.previousProxyHost = credHost
            self.previousProxyPort = credPort
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
        dict[ProviderConfig.LOW_POWER_MODE_KEY] = lowPowerMode

        let proxyMode: String
        switch proxyModeIndex {
        case 1: proxyMode = "manual"
        case 2: proxyMode = "system"
        default: proxyMode = "none"
        }
        dict[ProviderConfig.PROXY_MODE_KEY] = proxyMode
        dict[ProviderConfig.PROXY_HOST_KEY] = proxyHost
        dict[ProviderConfig.PROXY_PORT_KEY] = proxyPort

        // Determine effective host/port for credential storage
        var effectiveHost = proxyHost
        var effectivePort = UInt16(proxyPort) ?? 0
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
        if proxyMode != "none" && !proxyUsername.isEmpty && !proxyPassword.isEmpty && !effectiveHost.isEmpty && effectivePort > 0 {
            if let err = ZitiHttpProxyConfig.storeCredentials(
                username: proxyUsername, password: proxyPassword,
                proxyHost: effectiveHost, proxyPort: effectivePort) {
                zLog.error("Failed to store proxy credentials: \(err.localizedDescription)")
            }
        } else if !effectiveHost.isEmpty && effectivePort > 0 {
            ZitiHttpProxyConfig.deleteCredentials(proxyHost: effectiveHost, proxyPort: effectivePort)
        }

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
        return 2 // section 0: network, section 1: proxy
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 4 }
        if section == 1 { return 5 } // mode, host, port, username, password
        return 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1 { return "HTTP Proxy" }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell?

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
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                cell = tableView.dequeueReusableCell(withIdentifier: "PROXY_MODE_CELL", for: indexPath)
                if let proxyCell = cell as? ProxyModeCell {
                    proxyCell.setup(self, proxyModeIndex) { [weak self] index in
                        self?.proxyModeIndex = index
                        if index == 2, let sp = ZitiHttpProxyConfig.systemProxy() {
                            self?.proxyHost = sp.host
                            self?.proxyPort = String(sp.port)
                        } else if index != 1 {
                            self?.proxyHost = ""
                            self?.proxyPort = ""
                        }
                        self?.updateProxyFieldStates()
                    }
                }
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "TUNNEL_SETTING_CELL", for: indexPath)
                if let settingsCell = cell as? TunnelSettingsCell {
                    switch indexPath.row {
                    case 1:
                        settingsCell.setup(self, "Host", proxyHost, true) { [weak self] value in
                            self?.proxyHost = value
                        }
                        settingsCell.value.isEnabled = (proxyModeIndex == 1)
                    case 2:
                        settingsCell.setup(self, "Port", proxyPort, true) { [weak self] value in
                            self?.proxyPort = value
                        }
                        settingsCell.value.isEnabled = (proxyModeIndex == 1)
                        settingsCell.value.keyboardType = .numberPad
                    case 3:
                        settingsCell.setup(self, "Username", proxyUsername, false) { [weak self] value in
                            self?.proxyUsername = value
                        }
                        settingsCell.value.isEnabled = (proxyModeIndex != 0)
                    case 4:
                        settingsCell.setup(self, "Password", proxyPassword, false) { [weak self] value in
                            self?.proxyPassword = value
                        }
                        settingsCell.value.isSecureTextEntry = true
                        settingsCell.value.isEnabled = (proxyModeIndex != 0)
                    default:
                        break
                    }
                }
            }
        }
        return cell! // Don't let this happen!
    }

    private func updateProxyFieldStates() {
        // Reload the proxy section rows to update enabled states
        let rows = (1...4).map { IndexPath(row: $0, section: 1) }
        tableView.reloadRows(at: rows, with: .none)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return nil
    }
}
