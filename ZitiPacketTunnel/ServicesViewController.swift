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

class ServicesViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    
    fileprivate enum ColumnNames {
        static let Name = "Name"
        static let Proto = "Protocols"
        static let Hostname = "Addresses"
        static let Port = "Ports"
        static let Posture = "Posture Checks"
    }
    
    var sortKey = ColumnNames.Name
    var ascending = true
    
    weak var zid:ZitiIdentity? {
        get {
            return representedObject as? ZitiIdentity
        }
        set {
            representedObject = newValue
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClick(_:))
        
        tableView.tableColumns[0].title = ColumnNames.Name
        tableView.tableColumns[0].sortDescriptorPrototype = NSSortDescriptor(key: ColumnNames.Name, ascending: true)
        tableView.tableColumns[1].title = ColumnNames.Proto
        tableView.tableColumns[1].sortDescriptorPrototype = NSSortDescriptor(key: ColumnNames.Proto, ascending: true)
        tableView.tableColumns[2].title = ColumnNames.Hostname
        tableView.tableColumns[2].sortDescriptorPrototype = NSSortDescriptor(key: ColumnNames.Hostname, ascending: true)
        tableView.tableColumns[3].title = ColumnNames.Port
        tableView.tableColumns[3].sortDescriptorPrototype = NSSortDescriptor(key: ColumnNames.Port, ascending: true)
        tableView.tableColumns[4].title = ColumnNames.Posture
        
        tableView.isEnabled = zid == nil ? false : true
        self.reloadData()
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first, let key = sortDescriptor.key else {
            zLog.wtf("invalid sortDescriptor")
            return
        }
        sortKey = key
        ascending = sortDescriptor.ascending
        self.reloadData()
    }
    
    func reloadData() {
        if sortKey == ColumnNames.Name {
            zid?.services.sort(by: {
                let a = $0.name ?? ""
                let b = $1.name ?? ""
                return ascending ? a < b : a > b
            })
        } else if sortKey == ColumnNames.Hostname {
            zid?.services.sort(by: {
                let a = $0.addresses ?? ""
                let b = $1.addresses ?? ""
                return ascending ? a < b : a > b
            })
        } else if sortKey == ColumnNames.Port {
            zid?.services.sort(by: {
                let a = $0.portRanges ?? ""
                let b = $1.portRanges ?? ""
                return ascending ? a < b : a > b
            })
        } else if sortKey == ColumnNames.Proto {
            zid?.services.sort(by: {
                let a = $0.protocols ?? ""
                let b = $1.protocols ?? ""
                return ascending ? a < b : a > b
            })
        }
        tableView?.reloadData()
    }
    
    @objc func tableViewDoubleClick(_ sender:AnyObject) {
        guard tableView.selectedRow >= 0, let zid = zid else { return }
        
        if zid.isEnabled {
            let e = JSONEncoder()
            e.outputFormatting = .prettyPrinted
            let svc = zid.services[tableView.selectedRow]
            if let j = try? e.encode(svc), let jStr = String(data:j, encoding:.utf8) {
                zLog.info(jStr)
                let alert = NSAlert()
                alert.messageText = "\(zid.id):\(zid.name)\n\(svc.name ?? svc.id ?? "")"                
                
                let scrollView = NSTextView.scrollableTextView()
                scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 250)
                let textView = scrollView.documentView as? NSTextView
                textView?.isEditable = false
                textView?.textStorage?.mutableString.setString(jStr)
                textView?.backgroundColor = .black
                textView?.textColor = .white
                textView?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                alert.accessoryView = scrollView
                alert.runModal()
            }
        } else {
            zLog.info("\(zid.id):\(zid.name) not enabled")
        }
    }
    
    override var representedObject: Any? {
        didSet {
            tableView?.isEnabled = zid == nil ? false : true
            
            let selectedRow = tableView?.selectedRow ?? 0
            self.reloadData()
            tableView?.selectRowIndexes([selectedRow], byExtendingSelection: false)
        }
    }
}

extension ServicesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return zid?.services.count ?? 0
    }
}

extension ServicesViewController: NSTableViewDelegate {
    fileprivate enum CellIdentifiers {
        static let NameCell = "NameCellID"
        static let ProtocolCell = "ProtocolCellID"
        static let HostnameCell = "HostnameCellID"
        static let PortCell = "PortCellID"
        static let PostureCell = "PostureCellID"
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let svc = zid?.services[row] else {
            return nil
        }
        
        var text = ""
        var cellIdentifier = ""
        
        if tableColumn == tableView.tableColumns[0] {
            text = svc.name ?? "-"
            cellIdentifier = CellIdentifiers.NameCell
        } else if tableColumn == tableView.tableColumns[1] {
            text = svc.protocols ?? ""
            cellIdentifier = CellIdentifiers.ProtocolCell
        } else if tableColumn == tableView.tableColumns[2] {
            text = svc.addresses ?? "-"
            cellIdentifier = CellIdentifiers.HostnameCell
        } else if tableColumn == tableView.tableColumns[3] {
            text = String(svc.portRanges ?? "")
            cellIdentifier = CellIdentifiers.PortCell
        } else if tableColumn == tableView.tableColumns[4] {            
            let zidMgr = ZidMgr()
            if zidMgr.postureChecksPassing(svc) {
                text = "PASS"
            } else {
                text = "FAIL"
                let fails = zidMgr.failingPostureChecks(svc)
                if fails.count > 0 {
                    text += " (\(fails.joined(separator: ",")))"
                }
            }
            cellIdentifier = CellIdentifiers.PostureCell
        }
        
        if let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        
        return nil
    }
}
