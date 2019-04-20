//
//  TableViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/9/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import UIKit
import NetworkExtension

class StatusCell: UITableViewCell {
    @IBOutlet weak var connectStatus: UILabel!
    @IBOutlet weak var connectSwitch: UISwitch!
    weak var tvc:TableViewController?
    
    func tunnelStatusDidChange(_ status: NEVPNStatus) {
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
            connectStatus.text = "Not Connected"
            connectSwitch.isOn = false
            break
        case .invalid:
            connectStatus.text = "Invalid"
            connectSwitch.isOn = false
            break
        case .reasserting:
            connectStatus.text = "Reasserting..."
            break
        @unknown default:
            connectStatus.text = "Unknown"
            connectSwitch.isOn = false
        }
    }
    
    @IBAction func connectSwitchChanged(_ sender: Any) {
        if connectSwitch.isOn {
            do {
                try tvc?.tunnelMgr.startTunnel()
            } catch {
                print(error)
                let alert = UIAlertController(
                    title:"Ziti Connect Error",
                    message: error.localizedDescription,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                tvc?.present(alert, animated: true, completion: nil)
                connectSwitch.isOn = false
            }
        } else {
            tvc?.tunnelMgr.stopTunnel()
        }
    }
}

class TableViewController: UITableViewController, UIDocumentPickerDelegate {
    
    static let providerBundleIdentifier = "io.netfoundry.ZitiMobilePacketTunnel.MobilePacketTunnelProvider"
    var tunnelMgr = TunnelMgr()
    var zidMgr = ZidMgr()
    var servicePoller = ServicePoller()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true

        // init the manager
        tunnelMgr.loadFromPreferences(TableViewController.providerBundleIdentifier) { tpm, error in
            DispatchQueue.main.async {
                print("done loading from prefs, error=\(error?.localizedDescription ?? "nil")")
                self.tableView.reloadData()
            }
        }
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            NSLog(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        tableView.reloadData()
        
        // TODO: for ios will prob need to do this from tunnel (maybe based on setting(s) configured in app??)
        servicePoller.zidMgr = zidMgr
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.servicePoller.startPolling { didChange, zid in
                DispatchQueue.main.async {
                    /* TODO
                     if zid == self?.zids[(self?.representedObject ?? 0) as! Int] {
                     self?.updateServiceUI(zId:zid)
                     }*/
                    if didChange {
                        _ = self.zidMgr.zidStore.store(zid)
                        if zid.isEnabled {
                            self.tunnelMgr.restartTunnel()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            return true
        }
        return false
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            return .insert
        }
        return .none
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var nRows = 1
        if section == 1 {
            nRows = zidMgr.zids.count + 1
        } else if section == 2 {
            nRows = 4
        }
        return nRows
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell?

        // Configure the cell...
        if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "STATUS_CELL", for: indexPath)
            if let statusCell = cell as? StatusCell {
                statusCell.tvc = self
                tunnelMgr.onTunnelStatusChanged = statusCell.tunnelStatusDidChange
            }
        } else if indexPath.section == 1 {
            if indexPath.row == zidMgr.zids.count {
                cell = tableView.dequeueReusableCell(withIdentifier: "ADD_IDENTITY_CELL", for: indexPath)
                //let btn = UIButton(type: .contactAdd)
                //btn.isUserInteractionEnabled = false
                //cell?.accessoryView = btn // For now.  Lookes better with green insert button...
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_CELL", for: indexPath)
                let zid = zidMgr.zids[indexPath.row]
                cell?.tag = indexPath.row
                cell?.textLabel?.text = zid.name
                cell?.detailTextLabel?.text = zid.id
                //cell?.imageView?.image = UIImage(named: "NSStatusNone")
                //cell?.imageView based on zid status
            }
        } else {
            // feedback, help, advanced, about
            if indexPath.row == 0 {
                cell = tableView.dequeueReusableCell(withIdentifier: "FEEDBACK_CELL", for: indexPath)
            } else if indexPath.row == 1 {
                cell = tableView.dequeueReusableCell(withIdentifier: "HELP_CELL", for: indexPath)
            } else if indexPath.row == 2 {
                cell = tableView.dequeueReusableCell(withIdentifier: "ADVANCED_CELL", for: indexPath)
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "ABOUT_CELL", for: indexPath)
            }
        }
        return cell! // Don't let this happen!
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "" // Ziti Connections"
        } else if section == 1 {
            return "Identities"
        }
        return nil
    }
    
    /*override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 && zidMgr.zids.count == 0 {
            return "No identities have been configured. Select Add Identity below to add one."
        } else if section == 2 {
            return "Begin enrollment process of new identity via Enrollment JWT provided by adminstrator"
        } 
        return nil
    }*/

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Selected row at \(indexPath)")
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            print("selected Identity row")
            let dp = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
            dp.modalPresentationStyle = .formSheet
            dp.allowsMultipleSelection = false
            dp.delegate = self
            self.present(dp, animated: true, completion: nil)
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        NSLog("picker cancelled")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        do {
            let url = urls[0]
            if url.startAccessingSecurityScopedResource() == false {
                throw ZitiError("Unable to access security scoped resource \(url.lastPathComponent)")
            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            try zidMgr.insertFromJWT(url, at: 0)
            tableView.reloadData()
            // TODO: segue to identity screen for this zid
        } catch let error as ZitiError {
            //panel.orderOut(nil)
            //TODO self.dialogAlert("Unable to add identity", error.localizedDescription)
            NSLog("Unable to add identity: \(error.localizedDescription)")
        } catch {
            //panel.orderOut(nil)
            //TODO: self.dialogAlert("JWT Error", error.localizedDescription)
            NSLog("JWT Error: \(error.localizedDescription)")
            return
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let avc = segue.destination as? AdvancedViewController {
            avc.tvc = self
        } else if let ivc = segue.destination as? IdentityViewController {
            ivc.tvc = self
            if let ip = tableView.indexPathForSelectedRow {
                let cell = tableView.cellForRow(at: ip)
                ivc.zid = zidMgr.zids[cell?.tag ?? 0]
            }
        }
    }
}
