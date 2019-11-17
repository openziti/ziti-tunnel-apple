//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import UIKit
import MessageUI

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
        zid.edge.enroll() { zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    _ = self.tvc?.zidMgr.zidStore.store(zid)
                    self.tableView.reloadData()
                    self.tvc?.tableView.reloadData()
                    
                    let alert = UIAlertController(
                        title:"Unable to enroll \(zid.name)",
                        message: zErr!.localizedDescription,
                        preferredStyle: .alert)
                    
                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("OK", comment: "Default action"),
                        style: .default))
                    self.present(alert, animated: true, completion: nil)
                    return
                }
                zid.enabled = true
                _ = self.tvc?.zidMgr.zidStore.store(zid)
                _ = self.tvc?.zidMgr.zidStore.storeCId(zid)
                self.tableView.reloadData()
                self.tvc?.tableView.reloadData()
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
                nRows = zid?.services?.count ?? 0
            } else {
                nRows = 1
            }
        }
        return nRows
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 2 && zid?.services?.count ?? 0 > 0 && zid?.isEnrolled ?? false {
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
                cell?.detailTextLabel?.text = zid?.getBaseUrl()
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
                cell?.textLabel?.text = zid?.services?[indexPath.row].name
                cell?.detailTextLabel?.text = "\(zid?.services?[indexPath.row].dns?.hostname ?? ""):\(zid?.services?[indexPath.row].dns?.port ?? -1)"
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
