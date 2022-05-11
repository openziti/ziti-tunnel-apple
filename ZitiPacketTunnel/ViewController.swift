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

import Cocoa
import NetworkExtension
import CZiti

class ViewController: NSViewController, NSTextFieldDelegate {
    @IBOutlet weak var connectButton: NSButton!
    @IBOutlet weak var connectStatus: NSTextField!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var box: NSBox!
    @IBOutlet weak var buttonsView: NSView!
    @IBOutlet weak var idEnabledBtn: NSButton!
    @IBOutlet weak var idLabel: NSTextField!
    @IBOutlet weak var idNameLabel: NSTextField!
    @IBOutlet weak var idNetworkLabel: NSTextField!
    @IBOutlet weak var idControllerStatusLabel: NSTextFieldCell!
    @IBOutlet weak var idEnrollStatusLabel: NSTextField!
    @IBOutlet weak var idExpiresAtLabel: NSTextField!
    @IBOutlet weak var idEnrollBtn: NSButton!
    @IBOutlet weak var idSpinner: NSProgressIndicator!
    @IBOutlet weak var mfaControls: NSStackView!
    @IBOutlet weak var mfaSwitch: NSSwitch!
    @IBOutlet weak var mfaAuthNowBtn: NSButton!
    @IBOutlet weak var mfaCodesBtn: NSButton!
    
    static var providerBundleIdentifier:String {
        guard let bid = Bundle.main.object(forInfoDictionaryKey: "MAC_EXT_IDENTIFIER") else {
            fputs("Invalid MAC_EXT_IDENTIFIER", stderr)
            return ""
        }
        return "\(bid)"
    }
    
    weak var servicesViewController:ServicesViewController? = nil
    var tunnelMgr = TunnelMgr.shared
    var zidMgr = ZidMgr()
    var enrollingIds:[ZitiIdentity] = []
    
    func tunnelStatusDidChange(_ status:NEVPNStatus) {
        connectButton.isEnabled = true
        switch status {
        case .connecting:
            connectStatus.stringValue = "Connecting..."
            connectButton.title = "Turn Ziti Off"
            break
        case .connected:
            connectStatus.stringValue = "Connected"
            connectButton.title = "Turn Ziti Off"
            break
        case .disconnecting:
            connectStatus.stringValue = "Disconnecting..."
            break
        case .disconnected:
            connectStatus.stringValue = "Not Connected"
            connectButton.title = "Turn Ziti On"
            break
        case .invalid:
            connectStatus.stringValue = "Invalid"
            break
        case .reasserting:
            connectStatus.stringValue = "Reasserting..."
            connectButton.isEnabled = false
            break
        @unknown default:
            zLog.warn("Unknown tunnel status")
            break
        }
        self.tableView.reloadData()
        tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        buttonsView.wantsLayer = true
        buttonsView.layer!.borderWidth = 1.0
        
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            buttonsView.layer!.borderColor = CGColor(gray: 0.25, alpha: 1.0)
        } else {
            buttonsView.layer!.borderColor = CGColor(gray: 0.75, alpha: 1.0)
        }
    }
    
    private func dateToString(_ date:Date) -> String {
        guard date != Date(timeIntervalSince1970: 0) else { return "unknown" }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .long, timeStyle: .long)
    }
    
    func updateServiceUI(zId:ZitiIdentity?=nil) {
        var mfaEnabled = false
        if let pp = tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol, let conf = pp.providerConfiguration, let mfaEnabledCfg = conf[ProviderConfig.ENABLE_MFA_KEY] as? Bool {
            mfaEnabled = mfaEnabledCfg
        }
        mfaControls.isHidden = !mfaEnabled
                
        if let zId = zId {
            let cs = zId.edgeStatus ?? ZitiIdentity.EdgeStatus(0, status:.None)
            var csStr = ""
            if zId.isEnrolled == false {
                csStr = "None"
            } else if cs.status == .PartiallyAvailable {
                csStr = "Partially Available"
            } else {
                csStr = cs.status.rawValue
            }
            csStr += " (as of \(DateFormatter().timeSince(cs.lastContactAt)))"
            
            box.alphaValue = 1.0
            idEnabledBtn.isEnabled = zId.isEnrolled
            idEnabledBtn.state = zId.isEnabled ? .on : .off
            mfaSwitch.isEnabled = true
            mfaSwitch.state = zId.isMfaEnabled ? .on : .off
            mfaAuthNowBtn.isEnabled = zId.isMfaEnabled
            mfaCodesBtn.isEnabled = zId.isMfaEnabled
            idLabel.stringValue = zId.id
            idNameLabel.stringValue = zId.name
            idNetworkLabel.stringValue = zId.czid?.ztAPI ?? ""
            idControllerStatusLabel.stringValue = zId.controllerVersion ?? "" //csStr
            idEnrollStatusLabel.stringValue = zId.enrollmentStatus.rawValue
            idExpiresAtLabel.stringValue = "(expiration: \(dateToString(zId.expDate))"
            idExpiresAtLabel.isHidden = zId.enrollmentStatus == .Enrolled
            idEnrollBtn.isHidden = zId.enrollmentStatus == .Pending ? false : true
            
            if enrollingIds.contains(zId) {
                idSpinner.startAnimation(nil)
                idSpinner.isHidden = false
                idEnrollStatusLabel.stringValue = "Enrolling"
                idEnrollBtn.isEnabled = false
            } else {
                idSpinner.stopAnimation(nil)
                idSpinner.isHidden = true
                idEnrollStatusLabel.stringValue = zId.enrollmentStatus.rawValue
                idEnrollBtn.isEnabled = zId.enrollmentStatus == .Pending
            }
        } else {
            box.alphaValue = 0.25
            idEnabledBtn.isEnabled = false
            idEnabledBtn.state = .off
            mfaSwitch.isEnabled = false
            mfaSwitch.state = .off
            mfaAuthNowBtn.isEnabled = false
            mfaCodesBtn.isEnabled = false
            idLabel.stringValue = "-"
            idNameLabel.stringValue = "-"
            idNetworkLabel.stringValue = "-"
            idControllerStatusLabel.stringValue = "-"
            idEnrollStatusLabel.stringValue = "-"
            idExpiresAtLabel.isHidden = true
            idEnrollBtn.isHidden = true
            idSpinner.isHidden = true
        }
        
        self.tableView.reloadData()
        tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
        
        if let svc = servicesViewController {
            svc.zid = zId
        }
    }
   
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self

        box.borderType = NSBorderType.lineBorder
        
        // init the manager
        tunnelMgr.tsChangedCallbacks.append(self.tunnelStatusDidChange)
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier) {_,_ in 
            DispatchQueue.main.async {
                self.updateServiceUI(zId: self.zidMgr.zids[self.representedObject as! Int])
            }
        }
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            zLog.error(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        
        tableView.reloadData()
        representedObject = 0
        tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
        
        // listen for newOrChanged
        NotificationCenter.default.addObserver(forName: .onNewOrChangedId, object: nil, queue: OperationQueue.main) { [self] notification in
            guard let zid = notification.userInfo?["zid"] as? ZitiIdentity else {
                zLog.error("Unable to retrieve identity from event notification")
                return
            }
            
            DispatchQueue.main.async {
                self.zidMgr.updateIdentity(zid)
                self.updateServiceUI(zId: self.zidMgr.zids[self.representedObject as! Int])
                
                if self.zidMgr.needsRestart(zid) {
                    self.tunnelMgr.restartTunnel()
                }
            }
        }
        
        // listen for removedId
        NotificationCenter.default.addObserver(forName: .onRemovedId, object: nil, queue: OperationQueue.main) { [self] notification in
            guard let id = notification.userInfo?["id"] as? Int else {
                zLog.error("Unable to retrieve identityfrom event notification")
                return
            }
            
            DispatchQueue.main.async {
                zLog.info("\(id) REMOVED")
                _ = self.zidMgr.loadZids()
                self.representedObject = Int(0)
                self.tunnelMgr.restartTunnel()
            }
        }
        
        // listen for Ziti IPC events
        NotificationCenter.default.addObserver(forName: .onAppexNotification, object: nil, queue: OperationQueue.main) { notification in
            guard let msg = notification.userInfo?["ipcMessage"] as? IpcMessage else {
                zLog.error("Unable to retrieve IPC message from event notification")
                return
            }
            guard msg.meta.msgType == .MfaAuthQuery, let zidStr = msg.meta.zid,
                  let zid = self.zidMgr.zids.first(where: { $0.id == zidStr }) else {
                zLog.error("Unsupported IPC message type \(msg.meta.msgType) for id \(msg.meta.zid ?? "nil")")
                return
            }
            DispatchQueue.main.async {
                self.doMfaAuth(zid)
            }
        }
    }

    override var representedObject: Any? {
        didSet {
            zidMgr.zids.count == 0 ? updateServiceUI() : updateServiceUI(zId: zidMgr.zids[representedObject as! Int])
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tcvc = segue.destinationController as? TunnelConfigViewController {
            tcvc.preferredContentSize = CGSize(width: 440, height: 340)
            tcvc.vc = self
        } else if let svc = segue.destinationController as? ServicesViewController {
            servicesViewController = svc
            if zidMgr.zids.count > 0 {
                svc.zid = zidMgr.zids[representedObject as! Int]
            }
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if (tableView.selectedRow >= 0) {
            if (representedObject as! Int) != tableView.selectedRow {
                representedObject = tableView.selectedRow
            }
        }
    }
    
    func dialogAlert(_ msg:String, _ text:String? = nil) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText =  text ?? ""
        alert.alertStyle = NSAlert.Style.critical
        alert.runModal()
    }
    
    func dialogOKCancel(question: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    func dialogForString(question: String, text: String) -> String? {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let txtView = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = txtView
        
        let response = alert.runModal()

        if (response == .alertFirstButtonReturn) {
            return txtView.stringValue
        }
        return nil // Cancel
    }

    @IBAction func onConnectButton(_ sender: NSButton) {
        if (sender.title == "Turn Ziti On") {
            do {
                try tunnelMgr.startTunnel()
            } catch {
                dialogAlert("Error starting tunnel", error.localizedDescription)
            }
        } else {
            tunnelMgr.stopTunnel()
        }
    }
    
    @IBAction func onEnableServiceBtn(_ sender: NSButton) {
        if zidMgr.zids.count > 0 {
            let zId = zidMgr.zids[representedObject as! Int]
            zId.enabled = sender.state == .on
            _ = zidMgr.zidStore.store(zId)
            updateServiceUI(zId:zId)
            tunnelMgr.restartTunnel()
        }
    }
    
    @IBAction func addIdentityButton(_ sender: Any) {
        guard let window = view.window else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jwt"]
        panel.title = "Select Enrollment JWT file"
        
        panel.beginSheetModal(for: window) { (result) in
            //DispatchQueue(label: "JwtLoader").async {
                if result == NSApplication.ModalResponse.OK {
                    do {
                        try self.zidMgr.insertFromJWT(panel.urls[0], at: 0)
                        DispatchQueue.main.async {
                            self.tableView.reloadData()
                            self.representedObject = 0
                            self.tableView.selectRowIndexes([self.representedObject as! Int], byExtendingSelection: false)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            panel.orderOut(nil)
                            self.dialogAlert("Unable to add identity", error.localizedDescription)
                        }
                    }
                }
            //}
        }
    }
    
    @IBAction func removeIdentityButton(_ sender: Any) {
        guard zidMgr.zids.count > 0 else { return }
        
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        let text = "Deleting identity \(zid.name) (\(zid.id)) can't be undone"
        if dialogOKCancel(question: "Are you sure?", text: text) == true {
            let error = zidMgr.zidStore.remove(zid)
            guard error == nil else {
                dialogAlert("Unable to remove identity", error!.localizedDescription)
                return
            }
            
            self.zidMgr.zids.remove(at: indx)
            tableView.reloadData()
            if indx >= self.zidMgr.zids.count {
                representedObject = self.zidMgr.zids.count - 1
            } else {
                representedObject = indx
            }
            tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
        }
    }
    
    func toggleMfa(_ zId:ZitiIdentity, _ flag:NSControl.StateValue) {
        //DispatchQueue.main.async {
            self.mfaSwitch.state = flag
            self.updateServiceUI(zId:zId)
        //}
    }
    
    func mfaVerify(_ zId:ZitiIdentity, _ mfaEnrollment:ZitiMfaEnrollment) {
        guard let provisioningUrl = mfaEnrollment.provisioningUrl else {
            zLog.error("Invalid provisioning URL")
            return
        }
        
        // TODO: create a 'real' screen with QR code and whatnot
        if let code = dialogForString(question: "Setup MFA", text: provisioningUrl) {
            let msg = IpcMfaVerifyRequestMessage(zId.id, code)
            tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                DispatchQueue.main.async {
                    guard zErr == nil else {
                        self.dialogAlert("Error sending provider message to verify MFA", zErr!.localizedDescription)
                        self.toggleMfa(zId, .off)
                        return
                    }
                    guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage,
                          let status = statusMsg.status else {
                        self.dialogAlert("IPC Error", "Unable to parse verification response message")
                        self.toggleMfa(zId, .off)
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Verification Error", Ziti.zitiErrorString(status: status))
                        self.toggleMfa(zId, .off)
                        return
                    }
                    
                    // Success!
                    zId.mfaVerified = true
                    zId.lastMfaAuth = Date()
                    _ = self.zidMgr.zidStore.store(zId)
                    self.updateServiceUI(zId:zId)
                    
                    // TODO: Show recovery codes to a "real" screen
                    let codes = mfaEnrollment.recoveryCodes?.joined(separator: ", ")
                    self.dialogAlert("Recovery Codes", codes ?? "no recovery codes available")
                }
            }
        } else {
            zLog.info("Setup MFA cancelled")
            zId.mfaEnabled = false
            zId.mfaVerified = false
            _ = self.zidMgr.zidStore.store(zId)
            self.toggleMfa(zId, .off)
        }
    }
    
    @IBAction func onMfaToggle(_ sender: Any) {
        guard tunnelMgr.status == .connected else {
            mfaSwitch.state = mfaSwitch.state == .on ? .off : .on
            dialogAlert("You must be Connected to change MFA state")
            return
        }
        
        if zidMgr.zids.count > 0 {
            let zId = zidMgr.zids[representedObject as! Int]
            guard zId.isEnabled else {
                mfaSwitch.state = mfaSwitch.state == .on ? .off : .on
                dialogAlert("Identity must be Enabled to change MFA state")
                return
            }
            
            if mfaSwitch.state == .on {
                let msg = IpcMfaEnrollRequestMessage(zId.id)
                tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                    DispatchQueue.main.async {
                        guard zErr == nil else {
                            self.dialogAlert("Error sending provider message to enable MFA", zErr!.localizedDescription)
                            self.toggleMfa(zId, .off)
                            return
                        }
                        guard let enrollResp = respMsg as? IpcMfaEnrollResponseMessage,
                            let mfaEnrollment = enrollResp.mfaEnrollment else {
                            self.dialogAlert("IPC Error", "Unable to parse enrollment response message")
                            self.toggleMfa(zId, .off)
                            return
                        }
                        
                        zId.mfaEnabled = true
                        zId.mfaVerified = mfaEnrollment.isVerified
                        _ = self.zidMgr.zidStore.store(zId)
                        self.updateServiceUI(zId:zId)
                        
                        if !zId.isMfaVerified {
                            self.mfaVerify(zId, mfaEnrollment)
                        }
                    }
                }
            } else {
                // only need to prompt for code if enrollment is verified (else can just send empty string)
                var code:String?
                if !zId.isMfaVerified {
                    code = ""
                } else {
                    code = dialogForString(question: "Authorize MFA", text: "Enter code to disable MFA for \(zId.name):\(zId.id)")
                }
                
                if let code = code { // will be nil if user hit Cancel when prompted...
                    let msg = IpcMfaRemoveRequestMessage(zId.id, code)
                    tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                        DispatchQueue.main.async {
                            guard zErr == nil else {
                                self.dialogAlert("Error sending provider message to disable MFA", zErr!.localizedDescription)
                                self.toggleMfa(zId, .on)
                                return
                            }
                            guard let removeResp = respMsg as? IpcMfaStatusResponseMessage,
                                  let status = removeResp.status else {
                                self.dialogAlert("IPC Error", "Unable to parse MFA removal response message")
                                self.toggleMfa(zId, .on)
                                return
                            }
                            
                            if status != Ziti.ZITI_OK {
                                self.dialogAlert("MFA Removal Error",
                                                 "Status code: \(status)\nDescription: \(Ziti.zitiErrorString(status: status))")
                                self.toggleMfa(zId, .on)
                            } else {
                                zLog.info("MFA removed for \(zId.name):\(zId.id)")
                                zId.mfaEnabled = false
                                _ = self.zidMgr.zidStore.store(zId)
                                self.updateServiceUI(zId:zId)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func doMfaAuth(_ zid:ZitiIdentity) {
        if let code = self.dialogForString(question: "Authorize MFA\n\(zid.name):\(zid.id)", text: "Enter your authentication code") {
            let msg = IpcMfaAuthQueryResponseMessage(zid.id, code)
            self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                DispatchQueue.main.async {
                    guard zErr == nil else {
                        self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                        return
                    }
                    guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage,
                          let status = statusMsg.status else {
                        self.dialogAlert("IPC Error", "Unable to parse auth response message")
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                        self.doMfaAuth(zid)
                        return
                    }
                    
                    // Success!
                    zid.lastMfaAuth = Date()
                    _ = self.zidMgr.zidStore.store(zid)
                    self.updateServiceUI(zId:zid)
                }
            }
        }
    }
    
    @IBAction func onMfaAuthNow(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        doMfaAuth(zid)
    }
    
    @IBAction func onMfaCodes(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        
        if let code = self.dialogForString(question: "Authorize MFA\n\(zid.name):\(zid.id)", text: "Enter your authentication code") {
            let msg = IpcMfaGetRecoveryCodesRequestMessage(zid.id, code)
            self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                DispatchQueue.main.async {
                    guard zErr == nil else {
                        self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                        return
                    }
                    guard let codesMsg = respMsg as? IpcMfaRecoveryCodesResponseMessage,
                          let status = codesMsg.status else {
                        self.dialogAlert("IPC Error", "Unable to parse recovery codees response message")
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                        self.onMfaCodes(sender)
                        return
                    }
                    
                    // Success!
                    let codes = codesMsg.codes?.joined(separator: ", ")
                    self.dialogAlert("Recovery Codes", codes ?? "no recovery codes available")
                }
            }
        }
    }
    
    @IBAction func onEnrollButton(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        enrollingIds.append(zid)
        updateServiceUI(zId: zid)
        
        guard let presentedItemURL = zidMgr.zidStore.presentedItemURL else {
            self.dialogAlert("Unable to enroll \(zid.name)", "Unable to access group container")
            return
        }
        
        let url = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false)
        let jwtFile = url.path
        
        // Ziti.enroll takes too long, needs to be done in background
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async {
                    self.enrollingIds.removeAll { $0.id == zid.id }
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = self.zidMgr.zidStore.store(zid)
                        self.updateServiceUI(zId:zid)
                        self.dialogAlert("Unable to enroll \(zid.name)", zErr != nil ? zErr!.localizedDescription : "invalid response")
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
                    _ = self.zidMgr.zidStore.store(zid)
                    self.updateServiceUI(zId:zid)
                    self.tunnelMgr.restartTunnel()
                }
            }
        }
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return zidMgr.zids.count
    }
}

extension ViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "defaultRow"), owner: nil) as? NSTableCellView {
            
            let zid = zidMgr.zids[row]
            cell.textField?.stringValue = zid.name
            
            let tunnelStatus = tunnelMgr.status
            var imageName:String = "NSStatusNone"
            
            if zid.isEnrolled == true, zid.isEnabled == true, let edgeStatus = zid.edgeStatus {
                switch edgeStatus.status {
                case .Available: imageName = (tunnelStatus == .connected) ?
                    "NSStatusAvailable" : "NSStatusPartiallyAvailable"
                case .PartiallyAvailable: imageName = "NSStatusPartiallyAvailable"
                case .Unavailable: imageName = "NSStatusUnavailable"
                default: imageName = "NSStatusNone"
                }
            }
            cell.imageView?.image = NSImage(named:imageName) ?? nil
            //cell.toolTip = "Tooltip for identity named \(zid.name)"
            return cell
        }
        return nil
    }
}

