//
//  TableViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/9/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import UIKit
import NetworkExtension
import JWTDecode

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
    
    static let providerBundleIdentifier = "com.ampifyllc.ZitiMobilePacketTunnel.MobilePacketTunnelProvider"
    var tunnelMgr = TunnelMgr()
    var zidStore = ZitiIdentityStore()
    var zids:[ZitiIdentity] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        // init the manager
        tunnelMgr.loadFromPreferences(TableViewController.providerBundleIdentifier) { tpm, error in
            DispatchQueue.main.async {
                print("done loading from prefs, error=\(error?.localizedDescription ?? "nil")")
                self.tableView.reloadData()
            }
        }
        
        // Load previous identities
        let (zids, err) = zidStore.loadAll()
        if err != nil && err!.errorDescription != nil {
            NSLog(err!.errorDescription!)
        }
        self.zids = zids ?? []
        tableView.reloadData()
        
        // GetServices timer - fire quickly, then every X secs
        // TODO: for ios will prob need to do this from tunnel (maybe based on setting(s) configured in app??)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.updateServicesTimerFired() // should: auth, then update services
            Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { timer in
                self.updateServicesTimerFired()
            }
        }
    }
    
    func updateServicesTimerFired() {
        zids.forEach { zid in
            if (zid.enrolled ?? false) == true && (zid.enabled ?? false) == true {
                zid.edge.getServices { [weak self] didChange, _ in
                    DispatchQueue.main.async {
                        /* TODO
                        if zid == self?.zids[(self?.representedObject ?? 0) as! Int] {
                            self?.updateServiceUI(zId:zid)
                        }*/
                        if didChange {
                            _ = self?.zidStore.store(zid)
                            if zid.isEnabled {
                                self?.tunnelMgr.restartTunnel()
                            }
                        }
                    }
                }
            /* TODO
            } else if zid == zids[self.representedObject as! Int] {
                updateServiceUI(zId:zid) */
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var nRows = 1
        if section == 1 {
            nRows = zids.count
        } else if section == 3 {
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
            cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_CELL", for: indexPath)
            let zid = zids[indexPath.row]
            cell?.textLabel?.text = zid.name
            cell?.detailTextLabel?.text = zid.id
            cell?.imageView?.image = UIImage(named: "NSStatusNone")
            //cell?.imageView based on zid status
        } else if indexPath.section == 2 {
            cell = tableView.dequeueReusableCell(withIdentifier: "ADD_IDENTITY_CELL", for: indexPath)
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
        } else if section == 1 && zids.count > 0 {
            return "Identities"
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 && zids.count == 0 {
            return "No identities have been configured. Select Add Identity below to add one."
        } else if section == 2 {
            return "Begin enrollment process of new identity via Enrollment JWT provided by adminstrator"
        } 
        return nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("Selected row at \(indexPath)")
        if indexPath.section == 2 && indexPath.row == 0 {
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
            
            let token = try String(contentsOf: url, encoding: .utf8)
            let jwt = try decode(jwt: token)
            
            // parse the body
            guard let data = try? JSONSerialization.data(withJSONObject:jwt.body),
                let ztid = try? JSONDecoder().decode(ZitiIdentity.self, from: data)
                else {
                    throw ZitiError("Unable to parse enrollment data")
            }
            
            // only support OTT
            guard ztid.method == .ott else {
                throw ZitiError("Only OTT Enrollment is supported by this application")
            }
            
            // alread have this one?
            guard zids.first(where:{$0.id == ztid.id}) == nil else {
                throw ZitiError("Duplicate Identity Not Allowed. Identy \(ztid.name) is already present with id \(ztid.id)")
            }
            
            // store it
            let error = self.zidStore.store(ztid)
            guard error == nil else {
                throw error!
            }
            
            // add it
            zids.insert(ztid, at: 0)
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
        }
    }
}
