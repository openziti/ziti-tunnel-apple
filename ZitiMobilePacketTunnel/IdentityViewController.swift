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
import MessageUI
import CZiti

class IdentityEnabledCell: UITableViewCell {
    weak var ivc:IdentityViewController?
    @IBOutlet weak var `switch`: UISwitch!
    @IBOutlet weak var label: UILabel!
    @IBAction func valueChanged(_ sender: Any) {
        ivc?.onEnabledValueChanged(self.switch.isOn)
    }
}

class ForgetIdentityCell: UITableViewCell {
    weak var ivc:IdentityViewController?
    @IBAction func onButton(_ sender: Any) {
        ivc?.onForgetIdentity()
    }
}

class EnrollIdentityCell: UITableViewCell {
    weak var ivc:IdentityViewController?
    @IBAction func onButton(_ sender: Any) {
        ivc?.onEnroll()
    }
}

class MfaAuthNowdCell : UITableViewCell {
    weak var ivc:IdentityViewController?
    @IBAction func onButton(_ sender: Any) {
        ivc?.doMfaAuth()
    }
}

class MfaCodesCell : UITableViewCell {
    weak var ivc:IdentityViewController?
    @IBAction func onButton(_ sender: Any) {
    }
}

class MfaNewCodesCell : UITableViewCell {
    weak var ivc:IdentityViewController?
    @IBAction func onButton(_ sender: Any) {
    }
}

class MfaEnabledCell : UITableViewCell {
    weak var ivc:IdentityViewController?
    
    @IBOutlet weak var mfaLockImageView: UIImageView!
    @IBOutlet weak var mfaSwitch: UISwitch!
    
    func refresh() {
        guard let zid = ivc?.zid else { return }
        
        let tStatus = TunnelMgr.shared.status
        mfaSwitch.isEnabled = zid.isEnabled && (tStatus == .connected || tStatus == .connecting)
        mfaSwitch.isOn = zid.isMfaEnabled
        
        mfaLockImageView.image = UIImage(systemName: "lock.slash")
        mfaLockImageView.tintColor = .systemGray
        let mfaPostureChecksFailing = zid.failingPostureChecks().filter({ $0 == "MFA"}).first != nil
        
        if zid.isEnabled && zid.isMfaEnabled && (tStatus == .connecting || tStatus == .connected) {
            mfaLockImageView.image = UIImage(systemName: "lock.fill")
            if zid.isMfaPending {
                mfaLockImageView.tintColor = .systemRed
            } else {
                if !mfaPostureChecksFailing {
                    mfaLockImageView.tintColor = .systemGreen
                } else {
                    mfaLockImageView.tintColor = .systemYellow
                }
            }
        } 
    }
    
    func toggleMfa(_ state:Bool) {
        mfaSwitch.isOn = state
        ivc?.tableView.reloadData()
        ivc?.tvc?.tableView.reloadData()
    }
    
    func mfaVerify(_ mfaEnrollment:ZitiMfaEnrollment) {
        guard let provisioningUrl = mfaEnrollment.provisioningUrl else {
            zLog.error("Invalid provisioning URL")
            return
        }
        zLog.info("MFA provisioningUrl: \(provisioningUrl)")
        
        let sb = UIStoryboard.init(name: "Main", bundle: Bundle.main)
        if let vc = sb.instantiateViewController(withIdentifier: "MFA_VERIFY_VC") as? MfaVerifyViewController {
            vc.provisioningUrl = provisioningUrl
            vc.completionHandler = { [weak self] code in
                guard let zid = self?.ivc?.zid else { return }
                
                if let code = code {
                    let msg = IpcMfaVerifyRequestMessage(zid.id, code)
                    TunnelMgr.shared.ipcClient.sendToAppex(msg) { respMsg, zErr in
                        DispatchQueue.main.async {
                            guard zErr == nil else {
                                self?.ivc?.dialogAlert("Error sending provider message to verify MFA", zErr!.localizedDescription)
                                zid.mfaEnabled = false
                                zid.mfaVerified = false
                                if let updatedZid = self?.ivc?.tvc?.zidStore.update(zid, [.Mfa]) {
                                    self?.ivc?.tvc?.zids.updateIdentity(updatedZid)
                                }
                                self?.toggleMfa(false)
                                return
                            }
                            guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage,
                                  let status = statusMsg.status else {
                                self?.ivc?.dialogAlert("IPC Error", "Unable to parse verification response message")
                                zid.mfaEnabled = false
                                zid.mfaVerified = false
                                if let updatedZid = self?.ivc?.tvc?.zidStore.update(zid, [.Mfa]) {
                                    self?.ivc?.tvc?.zids.updateIdentity(updatedZid)
                                }
                                self?.toggleMfa(false)
                                return
                            }
                            guard status == Ziti.ZITI_OK else {
                                self?.ivc?.dialogAlert("MFA Verification Error", Ziti.zitiErrorString(status: status))
                                zid.mfaEnabled = false
                                zid.mfaVerified = false
                                if let updatedZid = self?.ivc?.tvc?.zidStore.update(zid, [.Mfa]) {
                                    self?.ivc?.tvc?.zids.updateIdentity(updatedZid)
                                }
                                self?.toggleMfa(false)
                                return
                            }

                            // Success!
                            zid.mfaVerified = true
                            zid.mfaPending = false
                            zid.lastMfaAuth = Date()
                            if let updatedZid = self?.ivc?.tvc?.zidStore.update(zid, [.Mfa]) {
                                self?.ivc?.tvc?.zids.updateIdentity(updatedZid)
                            }

                            let codes = mfaEnrollment.recoveryCodes?.joined(separator: ", ")
                            self?.ivc?.dialogAlert("Recovery Codes", codes ?? "no recovery codes available")
                        }
                    }
                } else {
                    zLog.info("Setup MFA cancelled")
                    zid.mfaEnabled = false
                    zid.mfaVerified = false
                    if let updatedZid = self?.ivc?.tvc?.zidStore.update(zid, [.Mfa]) {
                        self?.ivc?.tvc?.zids.updateIdentity(updatedZid)
                    }
                    self?.toggleMfa(false)
                }
                vc.dismiss(animated: true)
            }
            self.window?.rootViewController?.present(vc, animated: true)
        }
    }
    
    @IBAction func onMfaToggle(_ sender: Any) {
        guard let zid = ivc?.zid else {
            zLog.error("Invalid identity")
            mfaSwitch.isOn = !mfaSwitch.isOn
            return
        }
        
        if mfaSwitch.isOn {
            enableMfa(zid)
        } else {
            // only prompt for code if enrollment is verified, else just send empty string
            if !zid.isMfaVerified {
                disableMfa(zid, "")
            } else {
                let sb = UIStoryboard.init(name: "Main", bundle: Bundle.main)
                if let vc = sb.instantiateViewController(withIdentifier: "MFA_CODE_VC") as? MfaCodeViewController {
                    vc.completionHandler = { [weak self] code in
                        if let code = code {
                            self?.disableMfa(zid, code)
                        } else { // cancel
                            DispatchQueue.main.async {
                                self?.ivc?.tableView.reloadData()
                            }
                        }
                        vc.dismiss(animated: true)
                    }
                    self.window?.rootViewController?.present(vc, animated: true)
                }
            }
        }
    }
    
    func enableMfa(_ zid:ZitiIdentity) {
        let msg = IpcMfaEnrollRequestMessage(zid.id)
        TunnelMgr.shared.ipcClient.sendToAppex(msg) { respMsg, zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    self.ivc?.dialogAlert("Error sending provider message to enable MFA", zErr!.localizedDescription)
                    self.toggleMfa(false)
                    return
                }
                guard let enrollResp = respMsg as? IpcMfaEnrollResponseMessage,
                    let mfaEnrollment = enrollResp.mfaEnrollment else {
                    self.ivc?.dialogAlert("IPC Error", "Unable to parse enrollment response message")
                    self.toggleMfa(false)
                    return
                }

                zid.mfaEnabled = true
                zid.mfaPending = true
                zid.mfaVerified = mfaEnrollment.isVerified
                if let zidStore = self.ivc?.tvc?.zidStore {
                    self.ivc?.zid = zidStore.update(zid, [.Mfa])
                    self.ivc?.tvc?.zids.updateIdentity(zid)
                }
                self.ivc?.tableView.reloadData()
                self.ivc?.tvc?.tableView.reloadData()

                if !zid.isMfaVerified {
                    self.mfaVerify(mfaEnrollment)
                }
            }
        }
    }
    
    func disableMfa(_ zid:ZitiIdentity, _ code:String) {
        let msg = IpcMfaRemoveRequestMessage(zid.id, code)
        TunnelMgr.shared.ipcClient.sendToAppex(msg) { respMsg, zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    self.ivc?.dialogAlert("Error sending provider message to disable MFA", zErr!.localizedDescription)
                    self.toggleMfa(true)
                    return
                }
                guard let removeResp = respMsg as? IpcMfaStatusResponseMessage,
                      let status = removeResp.status else {
                    self.ivc?.dialogAlert("IPC Error", "Unable to parse MFA removal response message")
                    self.toggleMfa(true)
                    return
                }

                if status != Ziti.ZITI_OK {
                    self.ivc?.dialogAlert("MFA Removal Error",
                                     "Status code: \(status)\nDescription: \(Ziti.zitiErrorString(status: status))")
                    self.toggleMfa(true)
                } else {
                    zLog.info("MFA removed for \(zid.name):\(zid.id)")
                    zid.mfaEnabled = false
                    if let zidStore = self.ivc?.tvc?.zidStore {
                        self.ivc?.zid = zidStore.update(zid, [.Mfa])
                        self.ivc?.tvc?.zids.updateIdentity(zid)
                    }
                    self.ivc?.tableView.reloadData()
                    self.ivc?.tvc?.tableView.reloadData()
                }
            }
        }
    }
}

class IdentityViewController: UITableViewController, MFMailComposeViewControllerDelegate {
    
    weak var tvc:TableViewController?
    var zid:ZitiIdentity?

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func dialogAlert(_ msg:String, _ text:String? = nil) {
        let alert = UIAlertController(
            title: msg,
            message: text,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Default action"),
            style: .default))
        self.present(alert, animated: true, completion: nil)
    }
    
    func onEnabledValueChanged(_ enabled:Bool) {
        if let zid = self.zid {
            zid.enabled = enabled
            self.zid = tvc?.zidStore.update(zid, [.Enabled])
            tableView.reloadData()
            tvc?.tunnelMgr.sendEnabledMessage(zid) { code in
                zLog.info("Completion response for Set Enabled \(zid.isEnabled) for \(zid.name):\(zid.id), with code \(code)")
            }
            tvc?.tableView.reloadData()
        }
    }
    
    func onForgetIdentity() {
        let alert = UIAlertController(
            title:"Are you sure?",
            message: "Deleting identity \(zid?.name ?? "") cannot be undone.",
            preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Default action"),
            style: .default,
            handler: { _ in
                if let zid = self.zid {
                    _ = self.tvc?.zidStore.remove(zid)
                    if let indx = self.tvc?.zids.firstIndex(of: zid) {
                        self.tvc?.zids.remove(at: indx)
                    }
                }
                self.navigationController?.popViewController(animated: true)
                self.tvc?.tableView.reloadData()
        }))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
        present(alert, animated: true, completion: nil)
    }
    
    func onEnroll() {
        guard let zid = self.zid else { return }
        guard let presentedItemURL = self.tvc?.zidStore.presentedItemURL else {
            let alert = UIAlertController(
                title:"Unable to enroll \(zid.name)",
                message: "Unable to access group container",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("OK", comment: "Default action"),
                style: .default))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        let url = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false)
        let jwtFile = url.path
        
        // Ziti.enroll takes too long, needs to be done in background
        let spinner = SpinnerViewController()
        addChild(spinner)
        spinner.view.frame = view.frame
        view.addSubview(spinner.view)
        spinner.didMove(toParent: self)
        
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async {
                    // lose the spinner
                    spinner.willMove(toParent: nil)
                    spinner.view.removeFromSuperview()
                    spinner.removeFromParent()
                    
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = self.tvc?.zidStore.store(zid)
                        self.tableView.reloadData()
                        self.tvc?.tableView.reloadData()
                        
                        let alert = UIAlertController(
                            title:"Unable to enroll \(zid.name)",
                            message: zErr != nil ? zErr!.localizedDescription : "",
                            preferredStyle: .alert)
                        
                        alert.addAction(UIAlertAction(
                            title: NSLocalizedString("OK", comment: "Default action"),
                            style: .default))
                        self.present(alert, animated: true, completion: nil)
                        return
                    }
                    
                    if zid.czid == nil {
                        zid.czid = CZiti.ZitiIdentity(id: zidResp.id, ztAPI: zidResp.ztAPI)
                    }
                    zid.czid?.ca = zidResp.ca
                    if zidResp.name != nil {
                        zid.czid?.name = zidResp.name
                    }
                    
                    zid.enabled = true
                    zid.enrolled = true
                    self.zid = self.tvc?.zidStore.update(zid, [.Enabled, .Enrolled, .CZitiIdentity])
                    self.tableView.reloadData()
                    self.tvc?.tableView.reloadData()
                    self.tvc?.tunnelMgr.restartTunnel()
                }
            }
        }
    }
    
    func doMfaAuth() {
        guard let zid = self.zid else { return }
        
        let sb = UIStoryboard.init(name: "Main", bundle: Bundle.main)
        if let vc = sb.instantiateViewController(withIdentifier: "MFA_CODE_VC") as? MfaCodeViewController {
            vc.completionHandler = { [weak self] code in
                if let code = code {
                    let msg = IpcMfaAuthQueryResponseMessage(zid.id, code)
                    TunnelMgr.shared.ipcClient.sendToAppex(msg) { respMsg, zErr in
                        DispatchQueue.main.async {
                            guard zErr == nil else {
                                self?.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                                return
                            }
                            guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage,
                                  let status = statusMsg.status else {
                                self?.dialogAlert("IPC Error", "Unable to parse auth response message")
                                return
                            }
                            guard status == Ziti.ZITI_OK else {
                                self?.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                                //self?.doMfaAuth(zid)
                                return
                            }

                            // Success!
                            zid.lastMfaAuth = Date()
                            zid.mfaPending = false
                            if let updatedZid = self?.tvc?.zidStore.update(zid, [.Mfa]) {
                                self?.tvc?.zids.updateIdentity(updatedZid)
                            }
                            DispatchQueue.main.async {
                                self?.tableView.reloadData()
                                vc.dismiss(animated: true)
                            }
                        }
                    }
                } else { // cancel
                    DispatchQueue.main.async {
                        self?.tableView.reloadData()
                        vc.dismiss(animated: true)
                    }
                }
            }
            self.present(vc, animated: true)
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var nRows = 1
        if section == 1 {
            // authNow button
            if let zid = self.zid {
                let tStatus = TunnelMgr.shared.status
                if zid.isEnabled && zid.isMfaEnabled && (tStatus == .connecting || tStatus == .connected) {
                    nRows += 1
                    
                    // codes and newCode buttons
                    if !zid.isMfaPending {
                        nRows += 2
                    }
                }
            }
        } else if section == 2 {
            nRows = 5
        } else if section == 3 {
            if zid?.isEnrolled ?? false {
                nRows = zid?.services.count ?? 0
            } else {
                nRows = 1
            }
        }
        return nRows
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 3 && zid?.services.count ?? 0 > 0 && zid?.isEnrolled ?? false {
            return "Services"
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell?
            
        if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_ENABLED_CELL", for: indexPath)
            if let ivCell = cell as? IdentityEnabledCell {
                ivCell.ivc = self
                ivCell.switch.isOn = zid?.isEnabled ?? false
                ivCell.switch.isEnabled = zid?.isEnrolled ?? false
                ivCell.label.isEnabled = ivCell.switch.isEnabled
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                cell = tableView.dequeueReusableCell(withIdentifier: "MFA_CELL", for: indexPath)
                if let mfaEnabledCell = cell as? MfaEnabledCell {
                    mfaEnabledCell.ivc = self
                    mfaEnabledCell.refresh()
                }
            } else if indexPath.row == 1 {
                cell = tableView.dequeueReusableCell(withIdentifier: "MFA_AUTH_NOW_CELL", for: indexPath)
                if let mfaAuthNowCell = cell as? MfaAuthNowdCell {
                    mfaAuthNowCell.ivc = self
                }
            } else if indexPath.row == 2 {
                cell = tableView.dequeueReusableCell(withIdentifier: "MFA_RECOVERY_CODES_CELL", for: indexPath)
                if let mfaCodesCell = cell as? MfaCodesCell {
                    mfaCodesCell.ivc = self
                }
            } else if indexPath.row == 3 {
                cell = tableView.dequeueReusableCell(withIdentifier: "MFA_NEW_RECOVERY_CODES_CELL", for: indexPath)
                if let mfaNewCodesCell = cell as? MfaNewCodesCell {
                    mfaNewCodesCell.ivc = self
                }
            }
        } else if indexPath.section == 2 {
            cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_VALUE_CELL", for: indexPath)
            if indexPath.row == 0 {
                cell?.textLabel?.text = "Name"
                cell?.detailTextLabel?.text = zid?.name
            } else if indexPath.row == 1 {
                cell?.textLabel?.text = "Network"
                cell?.detailTextLabel?.text = zid?.czid?.ztAPI
            } else if indexPath.row == 2 {
                cell?.textLabel?.text = "Version"
                cell?.detailTextLabel?.text = zid?.controllerVersion ?? "unknown"
            } else if indexPath.row == 3 {
                cell?.textLabel?.text = "Status"
                let cs = zid?.edgeStatus ?? ZitiIdentity.EdgeStatus(0, status:.None)
                var csStr = ""
                if zid?.isEnrolled ?? false == false {
                    csStr = "None"
                } else if cs.status == .PartiallyAvailable {
                    csStr = "Partially Available"
                } else {
                    csStr = cs.status.rawValue
                }
                //csStr += " (as of \(DateFormatter().timeSince(cs.lastContactAt)))"
                cell?.detailTextLabel?.text = csStr
            } else {
                cell?.textLabel?.text = "Enrollment Status"
                cell?.detailTextLabel?.text = zid?.enrollmentStatus.rawValue
            }
        } else if indexPath.section == 3 {
            if let zid = zid, zid.isEnrolled {
                cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_SERVICE_CELL", for: indexPath)
                cell?.textLabel?.text = zid.services[indexPath.row].name
                
                var protoStr = ""
                if let protos = zid.services[indexPath.row].protocols {
                    protoStr = "\(protos)"
                }
                cell?.detailTextLabel?.text = "[\(protoStr)]:\(zid.services[indexPath.row].addresses ?? ""):[\(zid.services[indexPath.row].portRanges ?? "-1")] "
                
                let tunnelStatus = tvc?.tunnelMgr.status ?? .disconnected
                var imageName:String = "StatusNone"
                
                if tunnelStatus == .connected, zid.isEnrolled == true, zid.isEnabled == true, let svcStatus = zid.services[indexPath.row].status {
                    switch svcStatus.status {
                    case .Available: imageName = "StatusAvailable"
                    case .PartiallyAvailable: imageName = "StatusPartiallyAvailable"
                    case .Unavailable: imageName = "StatusUnavailable"
                    default: imageName = "StatusNone"
                    }
                }
                cell?.imageView?.image = UIImage(named: imageName)
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_ENROLL_CELL", for: indexPath)
                if let ivCell = cell as? EnrollIdentityCell { ivCell.ivc = self }
            }
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_FORGET_CELL", for: indexPath)
            if let ivCell = cell as? ForgetIdentityCell { ivCell.ivc = self }
        }
        return cell! // Don't let this happen!
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let svcVc = segue.destination as? ServiceViewController {
            if let ip = tableView.indexPathForSelectedRow, ip.section == 2 {
                svcVc.svc = zid?.services[ip.row]
            }
        }
    }
}
