//
//  ViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa
import NetworkExtension

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
    
    static let providerBundleIdentifier = "com.ampifyllc.ZitiPacketTunnel.PacketTunnelProvider"
    weak var servicesViewController:ServicesViewController? = nil
    var tunnelMgr = TunnelMgr()
    var zidMgr = ZidMgr()
    var enrollingIds:[ZitiIdentity] = []
    var servicePoller = ServicePoller()
    
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
            connectStatus.stringValue = "Disconnected"
            connectButton.title = "Turn Ziti On"
            break
        case .invalid:
            print("Invalid")
            break
        case .reasserting:
            connectStatus.stringValue = "Reasserting..."
            connectButton.isEnabled = false
            break
        @unknown default:
            print("Unknown...")
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
            idNetworkLabel.stringValue = zId.apiBaseUrl
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
    }
   
    override func viewDidLoad() {
        super.viewDidLoad()
        zidMgr.zidStore.delegate = self
        tableView.delegate = self
        tableView.dataSource = self

        box.borderType = NSBorderType.lineBorder
        
        // init the manager
        tunnelMgr.onTunnelStatusChanged = self.tunnelStatusDidChange
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier)
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            NSLog(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        
        tableView.reloadData()
        representedObject = 0
        tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
        
        servicePoller.zidMgr = zidMgr
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.servicePoller.startPolling { didChange, zid in
                DispatchQueue.main.async {
                    if zid == self.zidMgr.zids[self.representedObject as! Int] {
                        self.updateServiceUI(zId:zid)
                    }
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

    override var representedObject: Any? {
        didSet {
            zidMgr.zids.count == 0 ? updateServiceUI() : updateServiceUI(zId: zidMgr.zids[representedObject as! Int])
        }
    }
    
    func onRemovedId(_ idString: String) {
        print("zid \(idString) removed")
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        if let match = zidMgr.zids.first(where: { $0.id == zid.id }) {
            print("\(zid.name):\(zid.id) changed")
            
            // always take new service from tunneler...
            match.services = zid.services
            
            if zidMgr.zids.count > 0, match == zidMgr.zids[(representedObject ?? 0) as! Int] {
                updateServiceUI(zId:zid)
            }
        } else {
            print("\(zid.name):\(zid.id) new")
        }
        
        // Also TODO: add support for showning netSessions when present
        //print(zid.debugDescription)
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
            if result == NSApplication.ModalResponse.OK {
                do {
                    try self.zidMgr.insertFromJWT(panel.urls[0], at: 0)
                    self.tableView.reloadData()
                    self.representedObject = 0
                    self.tableView.selectRowIndexes([self.representedObject as! Int], byExtendingSelection: false)
                } catch let error as ZitiError {
                    panel.orderOut(nil)
                    self.dialogAlert("Unable to add identity", error.localizedDescription)
                } catch {
                    panel.orderOut(nil)
                    self.dialogAlert("JWT Error", error.localizedDescription)
                    return
                }
            }
        }
    }
    
    @IBAction func removeIdentityButton(_ sender: Any) {
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
    
    func doEnroll(_ zid:ZitiIdentity) {
        zid.edge.enroll() { zErr in
            DispatchQueue.main.async {
                self.enrollingIds.removeAll { $0.id == zid.id }
                guard zErr == nil else {
                    _ = self.zidMgr.zidStore.store(zid)
                    self.updateServiceUI(zId:zid)
                    self.dialogAlert("Unable to enroll \(zid.name)", zErr!.localizedDescription)
                    return
                }
                zid.enabled = true
                _ = self.zidMgr.zidStore.store(zid)
                self.updateServiceUI(zId:zid)
            }
        }
    }
    
    @IBAction func onEnrollButton(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        enrollingIds.append(zid)
        updateServiceUI(zId: zid)
        
        // Add rootCa to keychain here since we might need to prompt for updating keychain.
        // evaluating trust can be lengthy, and has to be done in the background. Actual
        // enrollment in that case will happen in an escaping callbak.  Otherwise will do
        // the enroll here (which is already async)
        var stillNeedToEnroll = true
        let zkc = ZitiKeychain()
        if let rootCa = zid.rootCa, let rootCaPem = zkc.extractPEMs("CERTIFICATE", allText: rootCa).last { //TODO: hack.  figure out if should find Root and use that, or should I add them all, add trust for root...
            let host = zid.edge.getHost()
            let der = zkc.convertToDER(rootCaPem)
            
            // do our best. if CA already trusted will be ok...
            let (cert, _) = zkc.storeCertificate(der, label: host)
            
            if let cert = cert {
                zid.rootCa = nil
                stillNeedToEnroll = false
                let status = zkc.evalTrustForCertificate(cert) { secTrust, result in
                    if result == .recoverableTrustFailure { // TODO: change ZitiEdge to just trust this bad boy?
                        let summary = SecCertificateCopySubjectSummary(cert)
                        DispatchQueue.main.sync {
                            if self.dialogOKCancel(question: "Trust Certificate from\n\"\(summary != nil ? summary! as String : host)\"?",
                                text: "Click OK to update your keychain.\n" +
                                    "(You may be prompted for your credentials for Keychain Access)") {
                                
                                if zkc.addTrustForCertificate(cert) == errSecSuccess {
                                    print("added trust for \(host)")
                                    //let result = zkc.evalTrustForCertificate(cert)
                                    //print("added trust for \(host), result=\(result.rawValue)")
                                }
                            }
                        }
                    }
                    self.doEnroll(zid)
                }
                if status != errSecSuccess {
                    stillNeedToEnroll = true
                }
            }
        }
        
        if stillNeedToEnroll {
            doEnroll(zid)
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

