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
    @IBOutlet weak var idCreatedAtLabel: NSTextField!
    @IBOutlet weak var idEnrollStatusLabel: NSTextField!
    @IBOutlet weak var idExpiresAtLabel: NSTextField!
    @IBOutlet weak var idEnrollBtn: NSButton!
    @IBOutlet weak var idSpinner: NSProgressIndicator!
    
    var servicesViewController:ServicesViewController? = nil
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
        print("Tunnel Status changed:")
        let status = self.tunnelProviderManager.connection.status
        switch status {
        case .connecting:
            print("Connecting...")
            connectStatus.stringValue = "Connecting..."
            connectButton.title = "Turn Ziti Off"
            break
        case .connected:
            print("Connected...")
            connectStatus.stringValue = "Connected"
            connectButton.title = "Turn Ziti Off"
            break
        case .disconnecting:
            print("Disconnecting...")
            connectStatus.stringValue = "Disconnecting..."
            break
        case .disconnected:
            print("Disconnected...")
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
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .long, timeStyle: .long)
    }
    
    private func updateServiceUI(zId:ZitiIdentity?=nil) {
        if let zId = zId {
            box.alphaValue = 1.0
            idEnabledBtn.isEnabled = true
            idEnabledBtn.state = zId.enabled ? .on : .off
            idLabel.stringValue = zId.id
            idNameLabel.stringValue = zId.name
            idNetworkLabel.stringValue = zId.apiBaseUrl
            idCreatedAtLabel.stringValue = zId.iat>0 ? dateToString(zId.iatDate):"unknown"
            idEnrollStatusLabel.stringValue = zId.enrollmentStatus.rawValue
            idExpiresAtLabel.stringValue = "(expiration: \(zId.exp>0 ? dateToString(zId.expDate):"unknown")"
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
            idCreatedAtLabel.stringValue = "-"
            idEnrollStatusLabel.stringValue = "-"
            idExpiresAtLabel.isHidden = true
            idEnrollBtn.isHidden = true
            idSpinner.isHidden = true
        }
        
        if let svc = servicesViewController {
            svc.updateServices(zId)
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
    }

    override var representedObject: Any? {
        didSet {
            zitiIdentities.count == 0 ? updateServiceUI() : updateServiceUI(zId: zitiIdentities[representedObject as! Int])
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tcvc = segue.destinationController as? TunnelConfigViewController {
            tcvc.tunnelProviderManager = self.tunnelProviderManager
        } else if let svc = segue.destinationController as? ServicesViewController {
            servicesViewController = svc
            //PIG set representedObj...
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if (tableView.selectedRow >= 0) {
            print("tableViewSelectionDidChange " + String(tableView.selectedRow))
            representedObject = tableView.selectedRow
        }
    }

    @IBAction func onConnectButton(_ sender: NSButton) {
        if (sender.title == "Turn Ziti On") {
            do {
                try self.tunnelProviderManager.connection.startVPNTunnel()
            } catch {
                NSAlert(error:error).runModal()
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
                    guard let ztid = ZitiIdentity(jwt.body) else {
                        throw ZitiError("Unable to parse enrollment data")
                    }
                    
                    // only support OTT
                    guard ztid.method == ZitiEnrollmentMethod.ott else {
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
                    self.dialogAlert("Unable to add identity", error.localizedDescription)
                } catch {
                    self.dialogAlert("JWT Error", error.localizedDescription)
                    return
                }
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
                self.updateServiceUI(zId:zid)
                guard zErr == nil else {
                    self.dialogAlert("Unable to enroll \(zid.name)", zErr!.localizedDescription)
                    return
                }
                
                // TODO:  Maybe set to Active?  Go grab initial set of Services? (or wait for TunnelProvider to get 'em?)
                print("ENROLLED!")
                
                zid.enabled = true
                _ = self.zidStore.store(zid)
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
            
            let zId = zitiIdentities[row]
            cell.textField?.stringValue = zId.name
            
            // None, Available, PartiallyAvailable, Unavailable
            cell.imageView?.image = NSImage(named:NSImage.Name(rawValue: "NSStatusNone")) ?? nil
            return cell
        }
        return nil
    }
}

