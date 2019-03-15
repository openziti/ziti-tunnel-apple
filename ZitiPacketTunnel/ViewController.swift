//
//  ViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa
import NetworkExtension
import JWTDecode

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
    
    weak var servicesViewController:ServicesViewController? = nil
    var zidStore = ZitiIdentityStore()
    
    static let providerBundleIdentifier = "com.ampifyllc.ZitiPacketTunnel.PacketTunnelProvider"
    var tunnelProviderManager: NETunnelProviderManager = NETunnelProviderManager()
    
    var zitiIdentities:[ZitiIdentity] = []
    var enrollingIds:[ZitiIdentity] = []
    
    private func initTunnelProviderManager() {
        
        NETunnelProviderManager.loadAllFromPreferences { (savedManagers: [NETunnelProviderManager]?, error: Error?) in
            if let error = error {
                NSLog(error.localizedDescription)
                // keep going - we still might need to set default values...
            }
            
            if let savedManagers = savedManagers {
                if savedManagers.count > 0 {
                    self.tunnelProviderManager = savedManagers[0]
                }
            }
            
            self.tunnelProviderManager.loadFromPreferences(completionHandler: { (error:Error?) in
                if let error = error {
                    NSLog(error.localizedDescription)
                }
                
                // This shouldn't happen unless first time run and no profile preference has been
                // imported, but handy for development...
                if self.tunnelProviderManager.protocolConfiguration == nil {
                    let providerProtocol = NETunnelProviderProtocol()
                    providerProtocol.providerBundleIdentifier = ViewController.providerBundleIdentifier
                    
                    let defaultProviderConf = ProviderConfig()
                    providerProtocol.providerConfiguration = defaultProviderConf.createDictionary()
                    providerProtocol.serverAddress = defaultProviderConf.serverAddress
                    providerProtocol.username = defaultProviderConf.username
                    
                    self.tunnelProviderManager.protocolConfiguration = providerProtocol
                    self.tunnelProviderManager.localizedDescription = defaultProviderConf.localizedDescription
                    self.tunnelProviderManager.isEnabled = true
                    
                    self.tunnelProviderManager.saveToPreferences(completionHandler: { (error:Error?) in
                        if let error = error {
                            NSLog(error.localizedDescription)
                        } else {
                            print("Saved successfully")
                        }
                    })
                }
                
                // update the Connect Button label
                self.tunnelStatusDidChange(nil)
            })
        }
    }
    
    @objc func tunnelStatusDidChange(_ notification: Notification?) {
        let status = self.tunnelProviderManager.connection.status
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
            print("Reasserting...")
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
            csStr += " (\(DateFormatter().timeSince(cs.lastContactAt)))"
            
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
        
        tableView.delegate = self
        tableView.dataSource = self

        box.borderType = NSBorderType.lineBorder
        
        // init the manager
        initTunnelProviderManager()
        
        // Load previous identities
        let (zids, err) = zidStore.load()
        if err != nil && err!.errorDescription != nil {
            NSLog(err!.errorDescription!)
        }
        self.zitiIdentities = zids ?? []
        self.tableView.reloadData()
        self.representedObject = 0
        tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
        
        // Get notified when tunnel status changes
        NotificationCenter.default.addObserver(self, selector:
            #selector(ViewController.tunnelStatusDidChange(_:)), name:
            NSNotification.Name.NEVPNStatusDidChange, object: nil)
        
        // GetServices timer - fire quickly, then every X secs
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.updateServicesTimerFired() // should: auth, then update services
            Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { timer in
                self.updateServicesTimerFired()
            }
        }
    }
    
    func updateServicesTimerFired() {
        zitiIdentities.forEach { zid in
            if (zid.enrolled ?? false) == true && (zid.enabled ?? false) == true {
                ZitiEdge(zid).getServices { zErr in
                    DispatchQueue.main.async {
                        if zid == self.zitiIdentities[(self.representedObject ?? 0) as! Int] {
                            self.updateServiceUI(zId:zid)
                        }
                    }
                }
            } else if zid == self.zitiIdentities[self.representedObject as! Int] {
                self.updateServiceUI(zId:zid)
            }
        }
    }

    override var representedObject: Any? {
        didSet {
            zitiIdentities.count == 0 ? updateServiceUI() : updateServiceUI(zId: zitiIdentities[representedObject as! Int])
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tcvc = segue.destinationController as? TunnelConfigViewController {
            tcvc.preferredContentSize = CGSize(width: 572, height: 270)
            tcvc.tunnelProviderManager = self.tunnelProviderManager
        } else if let svc = segue.destinationController as? ServicesViewController {
            servicesViewController = svc
            if zitiIdentities.count > 0 {
                svc.zid = zitiIdentities[representedObject as! Int]
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
                try self.tunnelProviderManager.connection.startVPNTunnel()
            } catch {
                dialogAlert("Tunnel Error", error.localizedDescription)
            }
        } else {
            self.tunnelProviderManager.connection.stopVPNTunnel()
        }
    }
    
    @IBAction func onEnableServiceBtn(_ sender: NSButton) {
        if zitiIdentities.count > 0 {
            let zId = zitiIdentities[representedObject as! Int]
            zId.enabled = sender.state == .on
            _ = zidStore.store(zId) // TODO: alert
            updateServiceUI(zId:zId)
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
                    let token = try String(contentsOf: panel.urls[0], encoding: .utf8)
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
                    guard self.zitiIdentities.first(where:{$0.id == ztid.id}) == nil else {
                        throw ZitiError("Duplicate Identity Not Allowed. Identy \(ztid.name) is already present with id \(ztid.id)")
                    }
                    
                    // store it
                    let error = self.zidStore.store(ztid)
                    guard error == nil else {
                        throw error!
                    }
                    
                    // add it
                    self.zitiIdentities.insert(ztid, at: 0)
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
        let zid = zitiIdentities[indx]
        let text = "Deleting identity \(zid.name) (\(zid.id)) can't be undone"
        if dialogOKCancel(question: "Are you sure?", text: text) == true {
            let error = zidStore.remove(zid)
            guard error == nil else {
                dialogAlert("Unable to remove identity", error!.localizedDescription)
                return
            }
            
            self.zitiIdentities.remove(at: indx)
            tableView.reloadData()
            if indx >= self.zitiIdentities.count {
                representedObject = self.zitiIdentities.count - 1
            } else {
                representedObject = indx
            }
            tableView.selectRowIndexes([representedObject as! Int], byExtendingSelection: false)
        }
    }
    
    @IBAction func onEnrollButton(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zitiIdentities[indx]
        enrollingIds.append(zid)
        updateServiceUI(zId: zid)
        ZitiEdge(zid).enroll() { zErr in
            DispatchQueue.main.async {
                self.enrollingIds.removeAll { $0.id == zid.id }
                guard zErr == nil else {
                    _ = self.zidStore.store(zid)
                    self.updateServiceUI(zId:zid)
                    self.dialogAlert("Unable to enroll \(zid.name)", zErr!.localizedDescription)
                    return
                }
                zid.enabled = true
                _ = self.zidStore.store(zid)
                self.updateServiceUI(zId:zid) // TODO: move to file change notify..
            }
        }
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.zitiIdentities.count
    }
}

extension ViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "defaultRow"), owner: nil) as? NSTableCellView {
            
            let zid = zitiIdentities[row]
            cell.textField?.stringValue = zid.name
            
            let tunnelStatus = self.tunnelProviderManager.connection.status
            var imageName:String = "NSStatusNone"
            
            if zid.isEnrolled == true, let edgeStatus = zid.edgeStatus {
                switch edgeStatus.status {
                case .Available: imageName = (tunnelStatus == .connected && zid.enabled == true) ?
                    "NSStatusAvailable" : "NSStatusPartiallyAvailable"
                case .PartiallyAvailable: imageName = "NSStatusPartiallyAvailable"
                case .Unavailable: imageName = "NSStatusUnavailable"
                default: imageName = "NSStatusNone"
                }
            }
            cell.imageView?.image = NSImage(named:NSImage.Name(rawValue: imageName)) ?? nil
            return cell
        }
        return nil
    }
}

