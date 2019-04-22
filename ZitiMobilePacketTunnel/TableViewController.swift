//
//  TableViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/9/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import UIKit
import NetworkExtension
import SafariServices

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
    weak var ivc:IdentityViewController?

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
                    self.ivc?.tableView.reloadData()
                    if didChange {
                        _ = self.zidMgr.zidStore.store(zid)
                        if zid.isEnabled {
                            self.tunnelMgr.restartTunnel()
                        }
                    }
                }
            }
        }
        
        /* -- not needed.  polling stops automagically when app moves to background...
         NotificationCenter.default.addObserver(forName: NSNotification.Name.NSExtensionHostDidEnterBackground, object: nil, queue: OperationQueue.main, using: { _ in
            print("NSExtensionHostDidEnterBackground - stop polling")
            self.servicePoller.stopPolling()
        })
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSExtensionHostWillEnterForeground, object: nil, queue: OperationQueue.main, using: { _ in
            print("NSExtensionHostWillEnterForeground - re-start polling")
            self.servicePoller.startPolling()
        })*/
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
                //cell?.accessoryView = btn // Lookes better with green insert button...
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

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Selected row at \(indexPath)")
        if indexPath.section == 1 && indexPath.row == zidMgr.zids.count {
            let dp = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
            dp.modalPresentationStyle = .formSheet
            dp.allowsMultipleSelection = false
            dp.delegate = self
            self.present(dp, animated: true, completion: nil)
        } else if indexPath.section == 2 && indexPath.row == 1 {
            // TODO: add real help...
            if let url = URL(string: "https://netfoundry.zendesk.com/hc/en-us/categories/360000991011-Docs-Guides") {
                let vc = SFSafariViewController(url: url)
                present(vc, animated: true)
            }
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
            tableView.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
            performSegue(withIdentifier: "IDENTITY_SEGUE", sender: self)
        } catch let error as ZitiError {
            let alert = UIAlertController(
                title:"Unable to add identity",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            present(alert, animated: true, completion: nil)
            NSLog("Unable to add identity: \(error.localizedDescription)")
        } catch {
            let alert = UIAlertController(
                title:"JWT Error",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            present(alert, animated: true, completion: nil)
            NSLog("JWT Error: \(error.localizedDescription)")
            return
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let avc = segue.destination as? AdvancedViewController {
            avc.tvc = self
        } else if let ivc = segue.destination as? IdentityViewController {
            self.ivc = ivc
            ivc.tvc = self
            if let ip = tableView.indexPathForSelectedRow {
                let cell = tableView.cellForRow(at: ip)
                ivc.zid = zidMgr.zids[cell?.tag ?? 0]
            }
        }
    }
    
    @IBAction func unwindFromIdentity(_ sender:UIStoryboardSegue) {
        ivc = nil
    }
}
