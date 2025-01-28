//
// Copyright NetFoundry Inc.
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
import SafariServices
import MessageUI
import UniformTypeIdentifiers

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
        tvc?.tableView.reloadData()
        tvc?.ivc?.tableView.reloadData()
    }
    
    @IBAction func connectSwitchChanged(_ sender: Any) {
        #if targetEnvironment(simulator)
        tvc?.tunnelMgr.status = connectSwitch.isOn ? .connected : .disconnected
        #else
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
        #endif
    }
}

class TableViewController: UITableViewController, UIDocumentPickerDelegate, MFMailComposeViewControllerDelegate, ScannerDelegate {
    
    static var providerBundleIdentifier:String {
        guard let bid = Bundle.main.object(forInfoDictionaryKey: "IOS_EXT_IDENTIFIER") else {
            fputs("Invalid IOS_EXT_IDENTIFIER", stderr)
            return ""
        }
        return "\(bid)"
    }
    var tunnelMgr = TunnelMgr.shared
    var zids:[ZitiIdentity] {
        get { return tunnelMgr.zids }
        set { tunnelMgr.zids = newValue }
    }
    var zidStore:ZitiIdentityStore { return tunnelMgr.zidStore }
    weak var ivc:IdentityViewController?
    let sc = ScannerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        
        sc.delegate = self
        
        // watch for new URLs
        NotificationCenter.default.addObserver(self, selector: #selector(self.onNewUrlNotification(_:)), name: NSNotification.Name(rawValue: "NewURL"), object: nil)

        // init the manager
        tunnelMgr.loadFromPreferences(TableViewController.providerBundleIdentifier) { tpm, error in
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
        
        // Load previous identities
        let (loadedZids, err) = zidStore.loadAll()
        if err != nil || loadedZids == nil {
            zLog.warn(err?.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        self.zids = loadedZids ?? []
        
        tableView.reloadData()
        
        // listen for newOrChanged
        NotificationCenter.default.addObserver(forName: .onNewOrChangedId, object: nil, queue: OperationQueue.main) { [self] notification in
            guard let zid = notification.userInfo?["zid"] as? ZitiIdentity else {
                zLog.error("Unable to retrieve identity from event notification")
                return
            }
            
            DispatchQueue.main.async { [self] in
                let count = self.zids.count
                self.zids.updateIdentity(zid)
                
                // if user currently viewing this identity, make sure it's current
                if let currId = ivc?.zid?.id, currId == zid.id {
                    ivc?.zid = zid
                }
                
                if count != self.zids.count { // inserted at 0
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                        self.tableView.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
                        self.performSegue(withIdentifier: "IDENTITY_SEGUE", sender: self)
                    }
                    self.tunnelMgr.restartTunnel()
                }
                
                self.tableView.reloadData()
                self.ivc?.tableView.reloadData()
                
//                if zid.needsRestart() {
//                    self.tunnelMgr.restartTunnel()
//                }
            }
        }
        
        // listen for removedId
        NotificationCenter.default.addObserver(forName: .onRemovedId, object: nil, queue: OperationQueue.main) { [self] notification in
            guard let id = notification.userInfo?["id"] as? String else {
                zLog.error("Unable to retrieve identity from event notification")
                return
            }
            
            DispatchQueue.main.async {
                zLog.info("\(id) REMOVED")
                let (loadedZids, _) = self.zidStore.loadAll()
                self.zids = loadedZids ?? []
                self.tableView.reloadData()
                self.ivc?.tableView.reloadData()
                self.tunnelMgr.restartTunnel()
            }
        }
        
        // Listen for appexNotifications
        NotificationCenter.default.addObserver(forName: .onAppexNotification, object: nil, queue: OperationQueue.main) { notification in
            guard let msg = notification.userInfo?["ipcMessage"] as? IpcMessage else {
                zLog.error("Unable to retrieve IPC message from event notification")
                return
            }
            
            // Process any specified action
            if msg.meta.msgType == .AppexNotificationAction, let msg = msg as? IpcAppexNotificationActionMessage {
                // Always select the zid (if specified)
                DispatchQueue.main.async {
                    let indx = self.zids.getZidIndx(msg.meta.zid)
                    if indx != -1 {
                        self.tableView.reloadData()
                        self.tableView.selectRow(at: IndexPath(row: indx, section: 1), animated: false, scrollPosition: .none)
                        self.performSegue(withIdentifier: "IDENTITY_SEGUE", sender: self)
                    }
                }
                
                // Process the action
                if let action = msg.action {
                    if action == UserNotifications.Action.MfaAuth.rawValue {
                        // put this on dispatch queue so it happens after the seque above (else ivc will be stale).
                        DispatchQueue.main.async {
                            self.ivc?.doMfaAuth()
                        }
                    } else if action == UserNotifications.Action.Restart.rawValue {
                        self.tunnelMgr.restartTunnel()
                    }
                }
            }
        }
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 1 && indexPath.row == zids.count {
            return true
        }
        return false
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == 1 && indexPath.row == zids.count {
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
            nRows = zids.count + 1
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
                tunnelMgr.tsChangedCallbacks.append(statusCell.tunnelStatusDidChange)
            }
        } else if indexPath.section == 1 {
            if indexPath.row == zids.count {
                cell = tableView.dequeueReusableCell(withIdentifier: "ADD_IDENTITY_CELL", for: indexPath)
                //let btn = UIButton(type: .contactAdd)
                //btn.isUserInteractionEnabled = false
                //cell?.accessoryView = btn // Lookes better with green insert button...
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_CELL", for: indexPath)
                let zid = zids[indexPath.row]
                cell?.tag = indexPath.row
                cell?.textLabel?.text = zid.name
                cell?.detailTextLabel?.text = zid.id
                
                let tunnelStatus = tunnelMgr.status
                var imageName:String = "StatusNone"
                
                if zid.isEnrolled == true, zid.isEnabled == true, let edgeStatus = zid.edgeStatus {
                    switch edgeStatus.status {
                    case .Available: imageName = (tunnelStatus == .connected) ?
                        "StatusAvailable" : "StatusPartiallyAvailable"
                    case .PartiallyAvailable: imageName = "StatusPartiallyAvailable"
                    case .Unavailable: imageName = "StatusUnavailable"
                    default: imageName = "StatusNone"
                    }
                }
                cell?.imageView?.image = UIImage(named: imageName)
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
    
    func deviceName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
                
            }
        }
        if modelCode != nil {
            return String(cString: modelCode!, encoding: .utf8) ?? ""
        } else {
            return ""
        }
    }
    
    func addViaJWTFile() {
        let supportedTypes: [UTType] = [UTType.data]
        let dp = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        
        dp.modalPresentationStyle = .formSheet
        dp.allowsMultipleSelection = false
        dp.delegate = self
        self.present(dp, animated: true, completion: nil)
    }
    
    func addViaQRCode() {
        present(sc, animated: true)
    }
    
    func found(code: String?) {
        sc.dismiss(animated: true) {
            guard let code = code else { return }
            
            let secs = Int(NSDate().timeIntervalSince1970)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("QRScan\(secs).jwt")
            guard let data = code.data(using: .utf8) else {
                let alert = UIAlertController(
                    title:"Scan Error",
                    message: "Unable to decode scanned data",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Ok", comment: "Ok"),
                    style: .default,
                    handler: nil))
                DispatchQueue.main.async {
                    self.present(alert, animated: true, completion: nil)
                }
                return
            }
            
            do {
                try data.write(to: tempURL, options: .atomic)
                self.onNewUrl(tempURL)
            } catch {
                let alert = UIAlertController(
                    title:"Scan Error",
                    message: "Unable to store scanned data: \(error.localizedDescription)",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Ok", comment: "Ok"),
                    style: .default,
                    handler: nil))
                DispatchQueue.main.async {
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1 && indexPath.row == zids.count {
            let alert = UIAlertController(
                title:"Select Enrollment Method",
                message: "Which enrollment method would you like to use?",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("JWT File", comment: "JWT"),
                style: .default,
                handler: { _ in
                    self.addViaJWTFile()
            }))
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("QR Code", comment: "QR"),
                style: .default,
                handler: { _ in
                    self.addViaQRCode()
            }))
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Cancel", comment: "Cancel"),
                style: .default,
                handler: { _ in
            }))
            DispatchQueue.main.async {
                self.present(alert, animated: true, completion: nil)
            }
        } else if indexPath.section == 2 && indexPath.row == 0 {
            // quick 'n dirty support email composer.  TODO: Look into Instabug
            let supportEmail = Bundle.main.infoDictionary?["ZitiSupportEmail"] as? String ?? ""
            let supportSubj = Bundle.main.infoDictionary?["ZitiSupportSubject"] as? String ?? ""
            if MFMailComposeViewController.canSendMail() {
                let mail = MFMailComposeViewController()
                mail.mailComposeDelegate = self
                mail.setSubject(supportSubj)
                mail.setToRecipients([supportEmail])
                mail.setMessageBody("\n\n\nVersion: \(Version.str)\nOS \(Version.osVersion)\nDevice: \(deviceName())", isHTML: false)
                if let logger = Logger.shared {
                    if let url = logger.currLog(forTag: Logger.TUN_TAG), let data = try? Data(contentsOf: url) {
                        mail.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
                        let prev = url.appendingPathExtension("1")
                        if let prevData = try? Data(contentsOf: prev) {
                            mail.addAttachmentData(prevData, mimeType: "text/plain", fileName: prev.lastPathComponent)
                        }
                    }
                    if let url = logger.currLog(forTag: Logger.APP_TAG), let data = try? Data(contentsOf: url) {
                        mail.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
                        let prev = url.appendingPathExtension("1")
                        if let prevData = try? Data(contentsOf: prev) {
                            mail.addAttachmentData(prevData, mimeType: "text/plain", fileName: prev.lastPathComponent)
                        }
                    }
                }
                self.present(mail, animated: true)
            } else {
                zLog.warn("Mail view controller not available")
                let alert = UIAlertController(
                    title:"Mail view not available",
                    message: "Please email \(supportEmail) for assistance",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                self.present(alert, animated: true, completion: nil)
            }
        } else if indexPath.section == 2 && indexPath.row == 1 {
            let zitiHelpUrl = Bundle.main.infoDictionary?["ZitiHelpURL"] as? String ?? ""
            if let url = URL(string: zitiHelpUrl) {
                let vc = SFSafariViewController(url: url)
                present(vc, animated: true)
            }
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        zLog.debug("picker cancelled")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onNewUrl(urls[0])
    }
    
    @objc func onNewUrlNotification(_ notification: NSNotification) {
        if let dict = notification.userInfo as NSDictionary?, let url = dict["url"] as? URL {
            onNewUrl(url)
        }
    }
    
    func onNewUrl(_ url:URL) {
        DispatchQueue(label: "JwtLoader").async {
            do {
                try self.zids.insertFromJWT(url, self.zidStore, at: 0)
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.tableView.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
                    self.performSegue(withIdentifier: "IDENTITY_SEGUE", sender: self)
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title:"Unable to add identity",
                        message: error.localizedDescription,
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                    self.present(alert, animated: true, completion: nil)
                    zLog.error("Unable to add identity: \(error.localizedDescription)")
                }
            }
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
                ivc.zid = zids[cell?.tag ?? 0]
            }
        }
    }
    
    @IBAction func unwindFromIdentity(_ sender:UIStoryboardSegue) {
        ivc = nil
    }
}
