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

class IdentityViewController: UITableViewController, MFMailComposeViewControllerDelegate {
    
    weak var tvc:TableViewController?
    var zid:ZitiIdentity?

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func onEnabledValueChanged(_ enabled:Bool) {
        if let zid = self.zid {
            zid.enabled = enabled
            _ = tvc?.zidMgr.zidStore.store(zid)
            tableView.reloadData()
            tvc?.tunnelMgr.restartTunnel()
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
                    _ = self.tvc?.zidMgr.zidStore.remove(zid)
                    if let indx = self.tvc?.zidMgr.zids.firstIndex(of: zid) {
                        self.tvc?.zidMgr.zids.remove(at: indx)
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
        guard let presentedItemURL = self.tvc?.zidMgr.zidStore.presentedItemURL else {
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
                        _ = self.tvc?.zidMgr.zidStore.store(zid)
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
                    _ = self.tvc?.zidMgr.zidStore.store(zid)
                    self.tableView.reloadData()
                    self.tvc?.tableView.reloadData()
                    self.tvc?.tunnelMgr.restartTunnel()
                }
            }
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
            nRows = 5
        } else if section == 2 {
            if zid?.isEnrolled ?? false {
                nRows = zid?.services.count ?? 0
            } else {
                nRows = 1
            }
        }
        return nRows
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 2 && zid?.services.count ?? 0 > 0 && zid?.isEnrolled ?? false {
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
                csStr += " (as of \(DateFormatter().timeSince(cs.lastContactAt)))"
                cell?.detailTextLabel?.text = csStr
            } else {
                cell?.textLabel?.text = "Enrollment Status"
                cell?.detailTextLabel?.text = zid?.enrollmentStatus.rawValue
            }
        } else if indexPath.section == 2 {
            if zid?.isEnrolled ?? false {
                cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_SERVICE_CELL", for: indexPath)
                cell?.textLabel?.text = zid?.services[indexPath.row].name
                
                var protoStr = ""
                if let protos = zid?.services[indexPath.row].protocols {
                    protoStr = "(\(protos))"
                }
                cell?.detailTextLabel?.text = "\(zid?.services[indexPath.row].addresses ?? ""):[\(zid?.services[indexPath.row].portRanges ?? "-1")] \(protoStr)"
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
}
