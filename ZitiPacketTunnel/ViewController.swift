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

class ViewController: NSViewController, NSTextFieldDelegate, ZitiIdentityStoreDelegate {
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
    
    static let providerBundleIdentifier = "io.netfoundry.ZitiPacketTunnel.PacketTunnelProvider"
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
    
    private func updateServiceUI(zId:ZitiIdentity?=nil) {
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
            idLabel.stringValue = zId.id
            idNameLabel.stringValue = zId.name
            idNetworkLabel.stringValue = zId.czid?.ztAPI ?? ""
            idControllerStatusLabel.stringValue = csStr
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
        
        // if first time run, present dialog that App Store reviewer required
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "For Your Information"
                alert.informativeText = "There is no user data collected by this app and shared with NetFoundry."
                alert.alertStyle = NSAlert.Style.informational
                alert.runModal()
            }
        }
    }
   
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Logger.initShared(Logger.APP_TAG)
        zLog.info(Version.verboseStr)
        
        zidMgr.zidStore.delegate = self
        tableView.delegate = self
        tableView.dataSource = self

        box.borderType = NSBorderType.lineBorder
        
        // init the manager
        tunnelMgr.tsChangedCallbacks.append(self.tunnelStatusDidChange)
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier)
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            zLog.error(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        
        tableView.reloadData()
        representedObject = 0
        tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
    }

    override var representedObject: Any? {
        didSet {
            zidMgr.zids.count == 0 ? updateServiceUI() : updateServiceUI(zId: zidMgr.zids[representedObject as! Int])
        }
    }
    
    func onRemovedId(_ idString: String) {
        DispatchQueue.main.async {
            //if let match = self.zidMgr.zids.first(where: { $0.id == idString }) {
                // shouldn't happend unless somebody deletes the file.
                zLog.info("\(idString) REMOVED")
                _ = self.zidMgr.loadZids()
                self.representedObject = Int(0)
                self.tunnelMgr.restartTunnel()
            //}
        }
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        DispatchQueue.main.async {
            if let match = self.zidMgr.zids.first(where: { $0.id == zid.id }) {
                zLog.info("\(zid.name):\(zid.id) CHANGED")
                
                // TUN will disable if unable to start for zid
                match.edgeStatus = zid.edgeStatus
                match.enabled = zid.enabled
                
                // always take new service from tunneler...
                match.services = zid.services
                match.czid?.name = zid.name
            } else {
                // new one.  generally zids are only added by this app (so will be matched above).
                // But possible somebody could load one manually or some day via MDM or somesuch
                zLog.info("\(zid.name):\(zid.id) NEW")
                self.zidMgr.zids.append(zid)
            }
            self.updateServiceUI(zId: self.zidMgr.zids[self.representedObject as! Int])
            let needsRestart = zid.services.filter {
                if let status = $0.status, let needsRestart = status.needsRestart {
                    return needsRestart
                }
                return false
            }
            if needsRestart.count > 0 {
                self.tunnelMgr.restartTunnel()
            }
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tcvc = segue.destinationController as? TunnelConfigViewController {
            tcvc.preferredContentSize = CGSize(width: 572, height: 270)
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

    @IBAction func onConnectButton(_ sender: NSButton) {
        if (sender.title == "Turn Ziti On") {
            do {
                try tunnelMgr.startTunnel()
            } catch {
                dialogAlert("Tunnel Error", error.localizedDescription)
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
            return cell
        }
        return nil
    }
}

