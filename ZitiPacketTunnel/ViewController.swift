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

import Cocoa
import NetworkExtension
import CZiti
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

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
    @IBOutlet weak var mfaLockImageView: NSImageView!
    @IBOutlet weak var mfaSwitch: NSSwitch!
    @IBOutlet weak var mfaAuthNowBtn: NSButton!
    @IBOutlet weak var mfaCodesBtn: NSButton!
    @IBOutlet weak var mfaNewCodesBtn: NSButton!
    @IBOutlet weak var extAuthNowBtn: NSButton!
    
    static var providerBundleIdentifier:String {
        guard let bid = Bundle.main.object(forInfoDictionaryKey: "MAC_EXT_IDENTIFIER") else {
            fputs("Invalid MAC_EXT_IDENTIFIER", stderr)
            return ""
        }
        return "\(bid)"
    }
    
    weak var servicesViewController:ServicesViewController? = nil
    var tunnelMgr = TunnelMgr.shared
    var zids:[ZitiIdentity] {
        get { return tunnelMgr.zids }
        set { tunnelMgr.zids = newValue }
    }
    var zidStore:ZitiIdentityStore { return tunnelMgr.zidStore }
    var enrollingIds:[ZitiIdentity] = []
    var enableStatePendingIds:[ZitiIdentity] = []
    
    let notificationsPanel = NotificationsPanel()
    
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
        
        if let indx = self.representedObject as? Int, self.zids.count > 0 {
            // set mfaPending if disconnecting or re-connecting.  purely cosmetic for UI as appex will reset correctly when it starts
            for zid in zids {
                if zid.isMfaEnabled && status == .disconnecting || status == .disconnected {
                    zid.mfaPending = true
                }
            }
            self.updateServiceUI(zId: self.zids[indx])
        } else {
            self.tableView.reloadData()
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        buttonsView.wantsLayer = true
        if let layer = buttonsView.layer {
            layer.borderWidth = 1.0
            
            if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
                layer.borderColor = CGColor(gray: 0.25, alpha: 1.0)
            } else {
                layer.borderColor = CGColor(gray: 0.75, alpha: 1.0)
            }
        }
    }
    
    private func dateToString(_ date:Date) -> String {
        guard date != Date(timeIntervalSince1970: 0) else { return "unknown" }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .long, timeStyle: .long)
    }
    
    func updateServiceUI(zId:ZitiIdentity?=nil) {
                        
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
            
            if tunnelMgr.status != .connected { enableStatePendingIds = [] }
            if enableStatePendingIds.contains(where: { $0.id == zId.id }) {
                idEnabledBtn.isEnabled = false
            } else {
                idEnabledBtn.isEnabled = zId.isEnrolled
            }
            idEnabledBtn.state = zId.isEnabled ? .on : .off
            mfaSwitch.isEnabled = zId.isEnabled && (tunnelMgr.status == .connected || tunnelMgr.status == .connecting)
            mfaSwitch.state = zId.isMfaEnabled ? .on : .off
            mfaAuthNowBtn.isHidden = !(zId.isEnabled && zId.isMfaEnabled && (tunnelMgr.status == .connecting || tunnelMgr.status == .connected))
            mfaCodesBtn.isHidden = mfaAuthNowBtn.isHidden || zId.isMfaPending
            mfaNewCodesBtn.isHidden = mfaAuthNowBtn.isHidden || zId.isMfaPending
            extAuthNowBtn.isHidden = !(zId.isEnabled && zId.isExtAuthEnabled && (tunnelMgr.status == .connecting || tunnelMgr.status == .connected))
            extAuthNowBtn.image?.accessibilityDescription = "Extended Authentication: N/A"
            
            if !extAuthNowBtn.isHidden {
                extAuthNowBtn.contentTintColor = !zId.isExtAuthPending ? .systemGreen : .systemYellow
            }
            
            mfaLockImageView.image = NSImage(systemSymbolName: "lock.slash", accessibilityDescription: "MFA: N/A")
            mfaLockImageView.contentTintColor = nil
            let mfaPostureChecksFailing = zId.failingPostureChecks().filter({ $0 == "MFA"}).first != nil
            if !mfaAuthNowBtn.isHidden {
                if zId.isMfaPending {
                    // lock.open is confusing.  Just go with colors...
                    mfaLockImageView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "MFA: Pending")
                    mfaLockImageView.contentTintColor = .systemRed
                } else {
                    if !mfaPostureChecksFailing {
                        //mfaLockImageView.contentTintColor = .init(red: 0.16, green: 0.78, blue: 0.50, alpha: 1.0)
                        mfaLockImageView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "MFA: Session Authenticated")
                        mfaLockImageView.contentTintColor = .systemGreen
                    } else {
                        mfaLockImageView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "MFA: Session Authenticated, Posture Checks Failing")
                        mfaLockImageView.contentTintColor = .systemYellow
                        if let img = mfaLockImageView.image {
                            img.accessibilityDescription = img.accessibilityDescription ?? "" + ", MFA Posture Checks Failing"
                        }
                    }
                }
            } else if mfaPostureChecksFailing {
                mfaLockImageView.contentTintColor = .systemYellow
                mfaLockImageView.image?.accessibilityDescription = "MFA Posture Checks Failing"
            }
            mfaLockImageView.toolTip = mfaLockImageView.image?.accessibilityDescription
            
            idLabel.stringValue = zId.id
            idNameLabel.stringValue = zId.name
            idNetworkLabel.stringValue = zId.czid?.ztAPI ?? ""
            idControllerStatusLabel.stringValue = zId.controllerVersion ?? "" //csStr
            let enrollStatusStr = zId.enrollmentStatusDisplay
            idEnrollStatusLabel.stringValue = enrollStatusStr
            if let expDate = zId.expDate {
                idExpiresAtLabel.stringValue = "(expiration: \(dateToString(expDate))"
                idExpiresAtLabel.isHidden = zId.enrollmentStatus == .Enrolled
            } else {
                idExpiresAtLabel.isHidden = true
            }
            idEnrollBtn.isHidden = zId.enrollmentStatus == .Pending ? false : true
            
            if enrollingIds.contains(zId) {
                idSpinner.startAnimation(nil)
                idSpinner.isHidden = false
                idEnrollStatusLabel.stringValue = "Enrolling"
                idEnrollBtn.isEnabled = false
            } else {
                idSpinner.stopAnimation(nil)
                idSpinner.isHidden = true
                idEnrollStatusLabel.stringValue = enrollStatusStr
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
            mfaNewCodesBtn.isEnabled = false
            extAuthNowBtn.isEnabled = false
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
        if let indx = representedObject as? Int {
            tableView.selectRowIndexes([indx], byExtendingSelection: false)
        }
        
        if let svc = servicesViewController {
            svc.zid = zId
            svc.tunnelMgr = tunnelMgr
        }
    }
   
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(notificationsPanel)
        
        tableView.delegate = self
        tableView.dataSource = self

        box.boxType = .custom
        box.fillColor = .underPageBackgroundColor
        box.isTransparent = false
        
        // init the manager
        tunnelMgr.tsChangedCallbacks.append(self.tunnelStatusDidChange)
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier) {_,_ in 
            DispatchQueue.main.async {
                if let indx = self.representedObject as? Int, self.zids.count > 0 {
                    self.updateServiceUI(zId: self.zids[indx])
                }
            }
        }
        
        // Load previous identities
        let (loadedZids, err) = zidStore.loadAll()
        if err != nil || loadedZids == nil {
            zLog.warn(err?.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        self.zids = loadedZids ?? []
        
        tableView.reloadData()
        representedObject = 0
        tableView.selectRowIndexes([0], byExtendingSelection: false)
        
        // listen for newOrChanged
        NotificationCenter.default.addObserver(forName: .onNewOrChangedId, object: nil, queue: OperationQueue.main) { [self] notification in
            guard let zid = notification.userInfo?["zid"] as? ZitiIdentity else {
                zLog.error("Unable to retrieve identity from event notification")
                return
            }
            
            DispatchQueue.main.async {
                self.zids.updateIdentity(zid)
                self.enableStatePendingIds.removeAll { $0.id == zid.id }
                if let indx = self.representedObject as? Int {
                    self.updateServiceUI(zId: self.zids[indx])
                }
            }
        }
        
        // listen for removedId
        NotificationCenter.default.addObserver(forName: .onRemovedId, object: nil, queue: OperationQueue.main) { [self] notification in
            guard let id = notification.userInfo?["id"] as? String else {
                zLog.error("Unable to retrieve identityf rom event notification")
                return
            }
            
            DispatchQueue.main.async {
                zLog.info("\(id) REMOVED")
                let (loadedZids, _) = self.zidStore.loadAll()
                self.zids = loadedZids ?? []
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
            
            // Process any notifications
            if msg.meta.msgType == .AppexNotification, let msg = msg as? IpcAppexNotificationMessage {
                self.notificationsPanel.add(msg)
            }
            
            // Process any notification action
            if msg.meta.msgType == .AppexNotificationAction, let msg = msg as? IpcAppexNotificationActionMessage {
                DispatchQueue.main.async {
                    // Select the zid (if specified)
                    if let zidStr = msg.meta.zid {
                        var indx = -1
                        for i in 0..<self.zids.count {
                            if self.zids[i].id == zidStr {
                                indx = i
                                break
                            }
                        }
                        if indx != -1 {
                            self.representedObject = indx
                            self.tableView.selectRowIndexes([indx], byExtendingSelection: false)
                        }
                    }
                    
                    // Bring the app to the foreground
                    if let appD = NSApp.delegate as? AppDelegate {
                        appD.menuBar?.showPanel(nil)
                    }
                    
                    // Process the action
                    if let action = msg.action {
                        if action == UserNotifications.Action.MfaAuth.rawValue {
                            if let zidStr = msg.meta.zid, let zid = self.zids.first(where: { $0.id == zidStr }) {
                                self.doMfaAuth(zid)
                            }
                        } else if action == UserNotifications.Action.Restart.rawValue {
                            self.tunnelMgr.restartTunnel()
                        } else if action == UserNotifications.Action.ExtAuth.rawValue {
                            if let zidStr = msg.meta.zid, let zid = self.zids.first(where: { $0.id == zidStr }) {
                                self.doExtAuth(zid)
                            }
                        }
                    }
                }
            }
        }
    }

    override var representedObject: Any? {
        didSet {
            if let indx = representedObject as? Int {
                zids.count == 0 ? updateServiceUI() : updateServiceUI(zId: zids[indx])
            } else if zids.count == 0 {
                updateServiceUI()
            }
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tcvc = segue.destinationController as? TunnelConfigViewController {
            tcvc.preferredContentSize = CGSize(width: 575, height: 330)
            tcvc.vc = self
        } else if let svc = segue.destinationController as? ServicesViewController {
            servicesViewController = svc
            if let indx = representedObject as? Int, zids.count > 0 {
                svc.zid = zids[indx]
                svc.tunnelMgr = tunnelMgr
            }
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let indx = representedObject as? Int, tableView.selectedRow >= 0 {
            if indx != tableView.selectedRow {
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
    
    // simple dialog for showing recovery codes
    func showRecoveryCodes(_ zid:ZitiIdentity, _ codes:[String]?) {
        guard let codesStr = codes?.joined(separator: ", ") else {
            self.dialogAlert("Recovery Codes", "no recovery codes available")
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Recovery Codes"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Dismiss")
        
        let scrollView = NSScrollView(frame: NSRect(x:0, y:0, width: 200, height: 100))
        scrollView.hasVerticalScroller = true
        
        let clipView = NSClipView(frame: scrollView.bounds)
        clipView.autoresizingMask = [.width, .height]
        
        let textView = EditableNSTextView(frame: clipView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.string = codesStr
        
        clipView.documentView = textView
        scrollView.contentView = clipView
        
        alert.accessoryView = scrollView
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if textView.string.isEmpty {
                return
            }
            let savePanel = NSSavePanel()
            savePanel.title = "Save MFA Recovery Codes"
            savePanel.nameFieldStringValue = "RecoveryCodes-\(zid.name).txt"
            savePanel.prompt = "Save"
            savePanel.allowedContentTypes = [UTType.text]
            
            savePanel.begin { (result: NSApplication.ModalResponse) -> Void in
                if result == NSApplication.ModalResponse.OK {
                    if let panelURL = savePanel.url {
                        do {
                            try codesStr.write(to: panelURL, atomically: true, encoding: .utf8)
                        } catch {
                            self.dialogAlert("Unable to store file", error.localizedDescription)
                        }
                    }
                }
            }
            
        default: return
        }
    }
    
    // brute force a QR code to setup MFA for now...
    func setupMfaDialog(_ provisioningUrl:String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Setup MFA"
        //alert.informativeText = "Scan QR code and enter valid MFA"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 200, height: 229))
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.distribution = .fill
        //stack.translatesAutoresizingMaskIntoConstraints = false
                
        // QR Code
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(provisioningUrl.utf8)
        
        let qrSize = CGFloat(175)
        var qrImg = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "unavailable") ?? NSImage()
        if let outputImage = filter.outputImage {
            let scaledImg = outputImage.transformed(
                by: CGAffineTransform(scaleX: qrSize / outputImage.extent.size.width, y: qrSize / outputImage.extent.size.height))
            
            if let cgimg = context.createCGImage(scaledImg, from: scaledImg.extent) {
                qrImg = NSImage(cgImage: cgimg, size: NSSize(width: qrSize, height: qrSize))
            }
        }
        let imgView = NSImageView(image: qrImg)
        imgView.frame = NSRect(x: 0, y: 0, width: qrSize, height: qrSize)
        imgView.layer?.magnificationFilter = .nearest
        stack.addArrangedSubview(imgView)
        
        // Secret
        if let url = URL(string: provisioningUrl) {
            var secret:String = provisioningUrl
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true), let queryItems = components.queryItems {
                for i in queryItems {
                    if i.name == "secret" {
                        secret = i.value ?? provisioningUrl
                        break
                    }
                }
            }
            
            let urlTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
            let attributedString = NSMutableAttributedString(string: secret)
            attributedString.setAttributes([.link: url], range: NSMakeRange(0, secret.count))
            urlTextView.textStorage?.setAttributedString(attributedString)
            urlTextView.alignment = .center
            urlTextView.isEditable = false
            urlTextView.drawsBackground = false
            urlTextView.linkTextAttributes = [
                .foregroundColor: NSColor.blue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            stack.addArrangedSubview(urlTextView)
        }
        
        // Enter Code
        let codeTextView = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        stack.addArrangedSubview(codeTextView)
        
        alert.accessoryView = stack
        alert.window.initialFirstResponder = codeTextView
        
        let response = alert.runModal()
        if (response == .alertFirstButtonReturn) {
            return codeTextView.stringValue
        }
        return nil // Cancel
    }
    
    func dialogForString(question: String, text: String, width: Int = 200, height: Int = 24) -> String? {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let txtView = EditableNSTextField(frame: NSRect(x: 0, y: 0, width: width, height: height))
        alert.accessoryView = txtView
        alert.window.initialFirstResponder = txtView
        
        let response = alert.runModal()

        if (response == .alertFirstButtonReturn) {
            return txtView.stringValue
        }
        return nil // Cancel
    }
    
    func dialogForListSelect(question: String, text: String, options: [String]) -> String? {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let listView = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        listView.addItems(withTitles: options)
        alert.accessoryView = listView
        alert.window.initialFirstResponder = listView
        
        let response = alert.runModal()

        if (response == .alertFirstButtonReturn) {
            return listView.titleOfSelectedItem
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
        if let indx = representedObject as? Int, zids.count > 0 {
            let zId = zids[indx]
            zId.enabled = sender.state == .on
            zids[indx] = zidStore.update(zId, [.Enabled])
            enableStatePendingIds.append(zId)
            idEnabledBtn.isEnabled = false
            tunnelMgr.sendEnabledMessage(zId) { code in
                DispatchQueue.main.async {
                    zLog.info("Completion response received for Set Enabled \(zId.isEnabled) for \(zId.name):\(zId.id), with code \(code)")
                    self.enableStatePendingIds.removeAll { $0.id == zId.id }
                    if let indx = self.representedObject as? Int, self.zids.count > 0 {
                        self.updateServiceUI(zId: self.zids[indx])
                    }
                }
            }
        }
    }
    
    @IBAction func addIdentityJwt(_ sender: Any) {
        guard let window = view.window else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let jwtType = UTType(filenameExtension:"jwt") {
            panel.allowedContentTypes = [jwtType]
        }
        panel.title = "Select Enrollment JWT file"
        
        panel.beginSheetModal(for: window) { (result) in
            //DispatchQueue(label: "JwtLoader").async {
            if result == NSApplication.ModalResponse.OK {
                do {
                    try self.zids.insertFromJWT(panel.urls[0], self.zidStore, at: 0)
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                        self.representedObject = 0
                        self.tableView.selectRowIndexes([0], byExtendingSelection: false)
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
    
    @IBAction func addIdentityUrl(_ sender: Any) {
        guard view.window != nil else { return }
        
        let urlStr = dialogForString(question: "Controller URL", text: "Enter the controller URL", width: 400)
        if urlStr == nil { return }
        guard let ctrlUrl = URL(string: urlStr!) else {
            self.dialogAlert("\(urlStr!) is not a valid URL")
            return
        }
        
        do {
            try self.zids.insertFromURL(ctrlUrl, self.zidStore, at: 0)
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.representedObject = 0
                self.tableView.selectRowIndexes([0], byExtendingSelection: false)
            }
        } catch {
            self.dialogAlert("Unable to add identity", error.localizedDescription)
        }
    }
    
    @IBAction func addIdentityButton(_ sender: NSButton) {
        guard view.window != nil else { return }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "With JWT ...", action: #selector(addIdentityJwt(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "With URL ...", action: #selector(addIdentityUrl(_:)), keyEquivalent: ""))
        let location = NSPoint(x: 0, y: menu.size.height * -1) // Magic number to adjust the height.
        menu.popUp(positioning: nil, at: location, in: sender)
    }
    
    @IBAction func removeIdentityButton(_ sender: Any) {
        guard zids.count > 0 else { return }
        guard let indx = representedObject as? Int else { return }
        
        let zid = zids[indx]
        let text = "Deleting identity \(zid.name) (\(zid.id)) can't be undone"
        if dialogOKCancel(question: "Are you sure?", text: text) == true {
            let error = zidStore.remove(zid)
            guard error == nil else {
                dialogAlert("Unable to remove identity", error!.localizedDescription)
                return
            }
            
            self.zids.remove(at: indx)
            tableView.reloadData()
            if indx >= self.zids.count {
                representedObject = self.zids.count - 1
            } else {
                representedObject = indx
            }
            tableView.selectRowIndexes([indx], byExtendingSelection: false)
        }
    }
    
    func toggleMfa(_ zId:ZitiIdentity, _ flag:NSControl.StateValue) {
        self.mfaSwitch.state = flag
        self.updateServiceUI(zId:zId)
    }
    
    func mfaVerify(_ zId: ZitiIdentity, _ mfaEnrollment:ZitiMfaEnrollment) {
        guard let provisioningUrl = mfaEnrollment.provisioningUrl else {
            zLog.error("Invalid provisioning URL")
            return
        }
        zLog.info("MFA provisioningUrl: \(provisioningUrl)")
        
        //if let code = dialogForString(question: "Setup MFA", text: provisioningUrl) {
        if let code = setupMfaDialog(provisioningUrl) {
            let msg = IpcMfaVerifyRequestMessage(zId.id, code)
            tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                DispatchQueue.main.async {
                    guard zErr == nil else {
                        self.dialogAlert("Error sending provider message to verify MFA", zErr!.localizedDescription)
                        zId.mfaEnabled = false
                        zId.mfaVerified = false
                        let updatedZid = self.zidStore.update(zId, [.Mfa])
                        self.toggleMfa(updatedZid, .off)
                        return
                    }
                    guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage,
                          let status = statusMsg.status else {
                        self.dialogAlert("IPC Error", "Unable to parse verification response message")
                        zId.mfaEnabled = false
                        zId.mfaVerified = false
                        let updatedZid = self.zidStore.update(zId, [.Mfa])
                        self.toggleMfa(updatedZid, .off)
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Verification Error", Ziti.zitiErrorString(status: status))
                        zId.mfaEnabled = false
                        zId.mfaVerified = false
                        let updatedZid = self.zidStore.update(zId, [.Mfa])
                        self.toggleMfa(updatedZid, .off)
                        return
                    }
                    
                    // Success!
                    zId.mfaVerified = true
                    zId.mfaPending = false
                    zId.lastMfaAuth = Date()
                    let updatedZid = self.zidStore.update(zId, [.Mfa])
                    self.updateServiceUI(zId:updatedZid)
                    
                    self.showRecoveryCodes(zId, mfaEnrollment.recoveryCodes)
                }
            }
        } else {
            zLog.info("Setup MFA cancelled")
            zId.mfaEnabled = false
            zId.mfaVerified = false
            let updatedZid = self.zidStore.update(zId, [.Mfa])
            self.toggleMfa(updatedZid, .off)
        }
    }
    
    @IBAction func onMfaToggle(_ sender: Any) {
        guard tunnelMgr.status == .connected || tunnelMgr.status == .connecting else {
            mfaSwitch.state = mfaSwitch.state == .on ? .off : .on
            dialogAlert("You must be Connected to change MFA state")
            return
        }
        
        if let indx = representedObject as? Int, zids.count > 0 {
            var zId = zids[indx]
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
                        zId.mfaPending = true
                        zId.mfaVerified = mfaEnrollment.isVerified
                        zId = self.zidStore.update(zId, [.Mfa])
                        self.zids[indx] = zId
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
                                self.updateServiceUI(zId:zId)
                                return
                            }
                            guard let removeResp = respMsg as? IpcMfaStatusResponseMessage,
                                  let status = removeResp.status else {
                                self.dialogAlert("IPC Error", "Unable to parse MFA removal response message")
                                self.toggleMfa(zId, .on)
                                self.updateServiceUI(zId:zId)
                                return
                            }
                            
                            if status != Ziti.ZITI_OK {
                                self.dialogAlert("MFA Removal Error",
                                                 "Status code: \(status)\nDescription: \(Ziti.zitiErrorString(status: status))")
                                self.toggleMfa(zId, .on)
                            } else {
                                zLog.info("MFA removed for \(zId.name):\(zId.id)")
                                zId.mfaEnabled = false
                                zId = self.zidStore.update(zId, [.Mfa])
                                self.zids[indx] = zId
                                self.updateServiceUI(zId:zId)
                            }
                        }
                    }
                } else {
                    self.updateServiceUI(zId:zId)
                }
            }
        }
    }
    
    func doMfaAuth(_ zid: ZitiIdentity) {
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
                    zid.mfaPending = false
                    let updatedZid = self.zidStore.update(zid, [.Mfa])
                    self.updateServiceUI(zId:updatedZid)
                }
            }
        }
    }
    
    @IBAction func onMfaAuthNow(_ sender: Any) {
        guard let indx = representedObject as? Int else { return }
        let zid = zids[indx]
        doMfaAuth(zid)
    }
    
    @IBAction func onMfaCodes(_ sender: Any) {
        guard let indx = representedObject as? Int else { return }
        let zid = zids[indx]
        
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
                        self.dialogAlert("IPC Error", "Unable to parse recovery codes response message")
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                        self.onMfaCodes(sender)
                        return
                    }
                    
                    // Success!
                    self.showRecoveryCodes(zid, codesMsg.codes)
                }
            }
        }
    }
    
    @IBAction func onMfaNewCodes(_ sender: Any) {
        guard let indx = representedObject as? Int else { return }
        let zid = zids[indx]
        
        if let code = self.dialogForString(question: "Authorize MFA\n\(zid.name):\(zid.id)", text: "Enter your authentication code") {
            let msg = IpcMfaNewRecoveryCodesRequestMessage(zid.id, code)
            self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                DispatchQueue.main.async {
                    guard zErr == nil else {
                        self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                        return
                    }
                    guard let codesMsg = respMsg as? IpcMfaRecoveryCodesResponseMessage,
                          let status = codesMsg.status else {
                        self.dialogAlert("IPC Error", "Unable to parse recovery codes response message")
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                        self.onMfaCodes(sender)
                        return
                    }
                    
                    // Success!
                    self.showRecoveryCodes(zid, codesMsg.codes)
                }
            }
        }
    }
    
    /// called when handling notification. initiate ext auth immediately if only one provider exists, otherwise display combobox
    func doExtAuth(_ zid: ZitiIdentity) {
        if let providers = zid.jwtProviders {
            // save some clicking if there's only one provider
            if providers.count == 1, let provider = providers.first {
                doExternalAuth(zid, provider)
                return
            }
            let providerNames = providers.map(\.name)
            let providerName = dialogForListSelect(question: "External Authentication Required",
                                                   text: "Select authentication provider for '\(zid.name)'",
                                                   options: providerNames)
            if let provider = providers.first(where: { $0.name == providerName }) {
                doExternalAuth(zid, provider)
            }
        }
    }

    func doExternalAuth(_ zid: ZitiIdentity, _ provider: JWTProvider) {
        let msg = IpcExternalAuthRequestMessage(zid.id, provider.name)
        self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    self.dialogAlert("Error sending provider message to authenticate externally", zErr!.localizedDescription)
                    return
                }
                guard let statusMsg = respMsg as? IpcExternalAuthResponseMessage,
                      let urlString = statusMsg.url,
                      let url = URL(string: urlString) else {
                    self.dialogAlert("IPC Error", "Unable to parse auth response message")
                    return
                }
                
                let opened = NSWorkspace.shared.open(url)
                if !opened {
                    self.dialogAlert("Unable to open autentication URL \(urlString). Please copy and paste into your browser.")
                }
            }
        }
    }

    @IBAction func externalAuthProviderSelected(_ sender: Any) {
        guard let indx = representedObject as? Int else { return }
        let zid = zids[indx]
        zLog.info("zid: \(zid.debugDescription)")

        guard let mi = sender as? NSMenuItem else { return }
        guard let provider = mi.representedObject as? JWTProvider else { return }

        doExternalAuth(zid, provider)
    }

    @IBAction func onExternalAuth(_ sender: NSButton) {
        guard let indx = representedObject as? Int else { return }
        let zid = zids[indx]
        if let providers = zid.jwtProviders {
            guard view.window != nil else { return }
            
            // save some clicking if there's only one provider
            if providers.count == 1, let provider = providers.first {
                doExternalAuth(zid, provider)
                return
            }
            
            let menu = NSMenu()
            for case let provider? in providers {
                let mi = NSMenuItem(title: provider.name, action: #selector(externalAuthProviderSelected(_:)), keyEquivalent: "")
                mi.representedObject = provider
                menu.addItem(mi)
            }
            let location = NSPoint(x: 0, y: menu.size.height - 20)
            menu.popUp(positioning: nil, at: location, in: sender)
        }
    }

    @IBAction func onEnrollButton(_ sender: Any) {
        guard let indx = representedObject as? Int else { return }
        var zid = zids[indx]
        enrollingIds.append(zid)
        updateServiceUI(zId: zid)

        guard let presentedItemURL = zidStore.presentedItemURL else {
            self.dialogAlert("Unable to enroll \(zid.name)", "Unable to access group container")
            return
        }

        let jwtUrl = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false)
        let jwtFile = jwtUrl.path
        let hasJwt = FileManager.default.fileExists(atPath: jwtFile)

        // OTT JWT: direct enrollment (existing flow)
        if hasJwt && zid.getEnrollmentMethod() == .ott {
            performOttEnroll(zid: &zid, jwtFile: jwtFile, indx: indx)
            return
        }

        // Non-OTT (URL or network JWT): query providers then show enrollment options
        let source: String? = hasJwt ? jwtFile : zid.czid?.ztAPI
        guard let enrollSource = source else {
            enrollingIds.removeAll { $0.id == zid.id }
            updateServiceUI(zId: zid)
            dialogAlert("Unable to enroll \(zid.name)", "No JWT file or controller URL available")
            return
        }

        let queryCallback: ([ZitiEvent.JwtSigner]?, CZiti.ZitiError?) -> Void = { providers, zErr in
            DispatchQueue.main.async {
                guard zErr == nil, let providers = providers else {
                    // Provider query failed - fall back to basic enrollment
                    self.performBasicEnroll(zid: &zid, jwtFile: hasJwt ? jwtFile : nil,
                                           controllerURL: zid.czid?.ztAPI, indx: indx)
                    return
                }

                let hasCert = providers.contains { $0.canCertEnroll }
                let hasToken = providers.contains { $0.canTokenEnroll }

                if !hasCert && !hasToken {
                    // No cert/token providers available - basic enrollment
                    self.performBasicEnroll(zid: &zid, jwtFile: hasJwt ? jwtFile : nil,
                                           controllerURL: zid.czid?.ztAPI, indx: indx)
                    return
                }

                self.showEnrollmentOptions(hasCert: hasCert, hasToken: hasToken,
                                           providers: providers, zid: zid) { enrollTo, providerName in
                    guard let enrollTo = enrollTo else {
                        // User cancelled
                        self.enrollingIds.removeAll { $0.id == zid.id }
                        self.updateServiceUI(zId: zid)
                        return
                    }

                    switch enrollTo {
                    case .cert, .token:
                        self.performEnrollTo(mode: enrollTo, zid: &zid, provider: providerName,
                                             jwtFile: hasJwt ? jwtFile : nil,
                                             controllerURL: hasJwt ? nil : zid.czid?.ztAPI, indx: indx)
                    case .none:
                        self.performBasicEnroll(zid: &zid, jwtFile: hasJwt ? jwtFile : nil,
                                               controllerURL: zid.czid?.ztAPI, indx: indx)
                    }
                }
            }
        }

        DispatchQueue.global().async {
            if hasJwt {
                Ziti.queryProviders(jwtFile: enrollSource, cb: queryCallback)
            } else {
                Ziti.queryProviders(controllerURL: enrollSource, cb: queryCallback)
            }
        }
    }

    // MARK: - Enrollment Helpers

    func performOttEnroll(zid: inout ZitiIdentity, jwtFile: String, indx: Int) {
        var zid = zid
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async {
                    self.enrollingIds.removeAll { $0.id == zid.id }
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = self.zidStore.store(zid)
                        self.updateServiceUI(zId: zid)
                        self.dialogAlert("Unable to enroll \(zid.name)", zErr != nil ? zErr!.localizedDescription : "invalid response")
                        return
                    }
                    self.handleEnrollmentSuccess(zid: &zid, zidResp: zidResp, enrollTo: .none, indx: indx)
                }
            }
        }
    }

    func performBasicEnroll(zid: inout ZitiIdentity, jwtFile: String?, controllerURL: String?, indx: Int) {
        var zid = zid
        var handled = false
        DispatchQueue.global().async {
            let enrollCallback: (CZiti.ZitiIdentity?, CZiti.ZitiError?) -> Void = { zidResp, zErr in
                DispatchQueue.main.async {
                    guard !handled else { return }
                    handled = true
                    self.enrollingIds.removeAll { $0.id == zid.id }
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = self.zidStore.store(zid)
                        self.updateServiceUI(zId: zid)
                        self.dialogAlert("Unable to enroll \(zid.name)", zErr != nil ? zErr!.localizedDescription : "invalid response")
                        return
                    }
                    self.handleEnrollmentSuccess(zid: &zid, zidResp: zidResp, enrollTo: .none, indx: indx)
                }
            }

            if let jwtFile = jwtFile {
                Ziti.enroll(jwtFile, enrollCallback)
            } else if let controllerURL = controllerURL {
                Ziti.enroll(controllerURL: controllerURL, enrollCallback)
            }
        }
    }

    func performEnrollTo(mode: ZitiIdentity.EnrollTo, zid: inout ZitiIdentity, provider: String?,
                          jwtFile: String?, controllerURL: String?, indx: Int) {
        var zid = zid
        var handled = false
        let requestedType = (mode == .cert) ? "Device Certificate" : "User Session"

        let onAuth: (String) -> Void = { urlString in
            DispatchQueue.main.async {
                guard let url = URL(string: urlString) else {
                    self.dialogAlert("Invalid authentication URL: \(urlString)")
                    return
                }
                if !NSWorkspace.shared.open(url) {
                    self.dialogAlert("Unable to open authentication URL. Please copy and paste into your browser: \(urlString)")
                }
            }
        }

        let enrollCallback: (CZiti.ZitiIdentity?, CZiti.ZitiError?) -> Void = { zidResp, zErr in
            DispatchQueue.main.async {
                guard !handled else { return }
                handled = true
                NSApp.requestUserAttention(.informationalRequest)
                NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
                self.view.window?.makeKeyAndOrderFront(nil)
                self.enrollingIds.removeAll { $0.id == zid.id }
                if let zErr = zErr {
                    if zErr.isAlreadyEnrolled {
                        self.handleAlreadyEnrolled(zid: &zid, jwtFile: jwtFile,
                                                   controllerURL: controllerURL, indx: indx,
                                                   requestedType: requestedType)
                        return
                    }
                    self.updateServiceUI(zId: zid)
                    self.dialogAlert("Unable to enroll \(zid.name)", zErr.localizedDescription)
                    return
                }
                guard let zidResp = zidResp else {
                    self.updateServiceUI(zId: zid)
                    self.dialogAlert("Unable to enroll \(zid.name)", "invalid response")
                    return
                }
                self.handleEnrollmentSuccess(zid: &zid, zidResp: zidResp, enrollTo: mode, indx: indx)
            }
        }

        DispatchQueue.global().async {
            if let jwtFile = jwtFile {
                if mode == .cert {
                    Ziti.enrollToCert(jwtFile: jwtFile, provider: provider, onAuth: onAuth, enrollCallback)
                } else {
                    Ziti.enrollToToken(jwtFile: jwtFile, provider: provider, onAuth: onAuth, enrollCallback)
                }
            } else if let controllerURL = controllerURL {
                if mode == .cert {
                    Ziti.enrollToCert(controllerURL: controllerURL, provider: provider, onAuth: onAuth, enrollCallback)
                } else {
                    Ziti.enrollToToken(controllerURL: controllerURL, provider: provider, onAuth: onAuth, enrollCallback)
                }
            }
        }
    }

    func handleAlreadyEnrolled(zid: inout ZitiIdentity, jwtFile: String?,
                               controllerURL: String?, indx: Int, requestedType: String) {
        let info = ZitiIdentity.alreadyEnrolledInfo(requestedType: requestedType)
        let alert = NSAlert()
        alert.messageText = info.title
        alert.informativeText = info.detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: info.action)
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            self.performBasicEnroll(zid: &zid, jwtFile: jwtFile,
                                   controllerURL: controllerURL, indx: indx)
        } else {
            self.enrollingIds.removeAll { $0.id == zid.id }
            self.updateServiceUI(zId: zid)
        }
    }

    func handleEnrollmentSuccess(zid: inout ZitiIdentity, zidResp: CZiti.ZitiIdentity,
                                 enrollTo: ZitiIdentity.EnrollTo, indx: Int) {
        let idChanged = zid.applyEnrollmentResponse(zidResp, enrollTo: enrollTo, zidStore: zidStore)

        if !idChanged {
            zid = zidStore.update(zid, [.Enabled, .Enrolled, .CZitiIdentity, .EnrollTo])
        }
        if indx < zids.count {
            zids[indx] = zid
        }
        if idChanged {
            tableView.reloadData()
        }
        updateServiceUI(zId: zid)
        tunnelMgr.restartTunnel()
    }

    // MARK: - Enrollment Options Dialog

    func showEnrollmentOptions(hasCert: Bool, hasToken: Bool,
                               providers: [ZitiEvent.JwtSigner],
                               zid: ZitiIdentity,
                               completion: @escaping (ZitiIdentity.EnrollTo?, String?) -> Void) {
        // If only one type is available, auto-select it
        if hasCert && !hasToken {
            let certProviders = providers.filter { $0.canCertEnroll }
            selectProvider(from: certProviders, title: "Device Certificate Enrollment",
                          text: "Select authentication provider for '\(zid.name)'") { providerName in
                completion(providerName != nil ? .cert : nil, providerName)
            }
            return
        }
        if hasToken && !hasCert {
            let tokenProviders = providers.filter { $0.canTokenEnroll }
            selectProvider(from: tokenProviders, title: "User Session Enrollment",
                          text: "Select authentication provider for '\(zid.name)'") { providerName in
                completion(providerName != nil ? .token : nil, providerName)
            }
            return
        }

        // Both cert and token available - ask the user
        let alert = NSAlert()
        alert.messageText = "Select Enrollment Type"
        alert.informativeText = "Choose how to enroll '\(zid.name)'"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 100))

        // Use NSMatrix for proper radio button grouping
        let radioMatrix = NSMatrix(frame: NSRect(x: 0, y: 8, width: 340, height: 84),
                                   mode: .radioModeMatrix,
                                   cellClass: NSButtonCell.self,
                                   numberOfRows: 2, numberOfColumns: 1)
        radioMatrix.autorecalculatesCellSize = true
        radioMatrix.cellSize = NSSize(width: 340, height: 42)

        if let certCell = radioMatrix.cell(atRow: 0, column: 0) as? NSButtonCell {
            certCell.title = "Device Certificate\n    Permanent, tied to this machine"
            certCell.setButtonType(.radio)
            certCell.font = NSFont.systemFont(ofSize: 13)
        }
        if let tokenCell = radioMatrix.cell(atRow: 1, column: 0) as? NSButtonCell {
            tokenCell.title = "User Session\n    Requires periodic login, tied to user account"
            tokenCell.setButtonType(.radio)
            tokenCell.font = NSFont.systemFont(ofSize: 13)
        }

        // Default to User Session
        radioMatrix.selectCell(atRow: 1, column: 0)

        container.addSubview(radioMatrix)
        alert.accessoryView = container

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            completion(nil, nil)
            return
        }

        let enrollTo: ZitiIdentity.EnrollTo = (radioMatrix.selectedRow == 0) ? .cert : .token
        let matchingProviders = providers.filter {
            enrollTo == .cert ? $0.canCertEnroll : $0.canTokenEnroll
        }

        selectProvider(from: matchingProviders, title: "Select Provider",
                      text: "Select authentication provider for '\(zid.name)'") { providerName in
            completion(providerName != nil ? enrollTo : nil, providerName)
        }
    }

    func selectProvider(from providers: [ZitiEvent.JwtSigner], title: String, text: String,
                        completion: @escaping (String?) -> Void) {
        guard !providers.isEmpty else {
            completion(nil)
            return
        }

        // Single provider - auto-select
        if providers.count == 1 {
            completion(providers[0].name)
            return
        }

        // Multiple providers - show picker
        let providerNames = providers.map(\.name)
        let selected = dialogForListSelect(question: title, text: text, options: providerNames)
        completion(selected)
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return zids.count
    }
}

extension ViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "defaultRow"), owner: nil) as? NSTableCellView {
            
            let zid = zids[row]
            cell.textField?.stringValue = zid.name
            
            let tunnelStatus = tunnelMgr.status
            var imageName:String = "NSStatusNone"
            var tooltip:String?
            
            if zid.isEnabled && zid.isMfaEnabled && zid.isMfaPending {
                tooltip = "MFA Pending"
            } else if !zid.allServicePostureChecksPassing() {
                tooltip = "Posture check(s) failing"
            }
            
            if zid.isEnrolled == true, zid.isEnabled == true, let edgeStatus = zid.edgeStatus {
                switch edgeStatus.status {
                case .Available:
                    imageName = (tunnelStatus == .connected) ? "NSStatusAvailable" : "NSStatusPartiallyAvailable"
                case .PartiallyAvailable:
                    imageName = "NSStatusPartiallyAvailable"
                case .Unavailable:
                    imageName = "NSStatusUnavailable"
                default:
                    imageName = "NSStatusNone"
                }
                
                if tunnelStatus != .connected {
                    tooltip = "Status: \(connectStatus.stringValue)"
                } else if edgeStatus.status != .Available && zid.needsRestart() {
                    tooltip = "Connection reset may be required to access services"
                } else {
                    tooltip = "Controller Status: \(edgeStatus.status.rawValue)"
                }
            }
            cell.imageView?.image = NSImage(named:imageName) ?? nil
            cell.toolTip = tooltip // nil intentional if no tooltip set...
            return cell
        }
        return nil
    }
}

