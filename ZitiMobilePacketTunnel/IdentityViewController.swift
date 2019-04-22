//
//  IdentityViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/18/19.
//  Copyright © 2019 David Hart. All rights reserved.
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
    
    func doEnroll(_ zid:ZitiIdentity) {
        zid.edge.enroll() { zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    _ = self.tvc?.zidMgr.zidStore.store(zid)
                    self.tableView.reloadData()
                    
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
                self.tableView.reloadData()
            }
        }
    }
    
    func onEnroll() {
        guard let zid = self.zid else { return }
        
        let zkc = ZitiKeychain()
        let host = zid.edge.getHost()
        let caPoolPems = zid.rootCa != nil ? zkc.extractPEMs(zid.rootCa!) : []
        let status = zkc.processCaPool(caPoolPems, label:host) { certs, secTrust, result in
            if result == .recoverableTrustFailure {
                let summary = certs.first != nil ? SecCertificateCopySubjectSummary(certs.first!) : host as CFString
                
                // hoo-boy. To install cert, need to either install a profile. Via MDM, by opening cert as email
                // attachment, opening in safari, or opening in iCloud Drive.  Good times.  TODO: write JIRA ticket
                // to have Root CA emailed along with the JWT
                // See: https://nafejeries.wordpress.com/2015/07/11/programmatically-deploy-digital-certificates-to-the-ios-system-certificate-store/
                
                DispatchQueue.main.sync {
                    let alert = UIAlertController(
                        title:"Trust Certificate from\n\"\(summary != nil ? summary! as String : host)\"?",
                        message: "Download certificates by E-mailing to yourself. Once downloaded, select the file to create a Profile in Settings (Settings -> Profile Downloaded). Once Profile is installed, trust this certificate via Settings -> General -> About -> Certificate Trust Settings",
                        preferredStyle: .alert)
                    
                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("Email", comment: "Default action"),
                        style: .default,
                        handler: { _ in
                            if MFMailComposeViewController.canSendMail() {
                                let mail = MFMailComposeViewController()
                                mail.mailComposeDelegate = self
                                mail.setSubject("Certificate Chain")
                                //mail.setToRecipients(["you@yoursite.com"])
                                mail.setMessageBody("<p>Select attached certificates to download and create a Profiles in Settings (Settings -> Profile Downloaded).</p><p>Once Profile is installed for Root CA, trust this certificate via Settings -> General -> About -> Certificate Trust Settings</p>", isHTML: true)
                                /*
                                 // didn't work (Apple only installs first cert.  We need to trust the root).
                                let pemData = caPoolPems.joined().data(using: .utf8)! // Safe to force unwrap .utf8
                                mail.addAttachmentData(pemData, mimeType: "application/pem-certificate-chain", fileName: "certificate-chain.pem")
                                */
                                for i in 0..<certs.count {
                                    if zkc.isRootCa(certs[i]) {
                                        let summary = SecCertificateCopySubjectSummary(certs[i])
                                        let fn = String(summary ?? "certificate" as CFString) + ".pem"
                                        let pemData = caPoolPems[i].data(using: .utf8)! // Safe to force unwrap .utf8
                                        mail.addAttachmentData(pemData, mimeType: "application/pem-certificate-chain", fileName: fn)
                                    }
                                }
                                self.present(mail, animated: true)
                            } else {
                                print("Mail view controller not available")
                                let alert = UIAlertController(
                                    title:"Mail view not available",
                                    message: "Please contact admin and request Root CA for this site to be emailed to you.",
                                    preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                                self.present(alert, animated: true, completion: nil)
                            }
                        }))
                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("Cancel", comment: "Cancel"),
                        style: .cancel))
                    self.present(alert, animated: true, completion: nil)
                }
            } else {
                self.doEnroll(zid)
            }
        }
        if status != errSecSuccess {
            doEnroll(zid)
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
            nRows = 4
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
                cell?.detailTextLabel?.text = zid?.apiBaseUrl
            } else if indexPath.row == 2 {
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
