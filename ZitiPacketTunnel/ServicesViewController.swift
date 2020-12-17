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
    
    var sortKey:String? = "Name"
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
        
        tableView.tableColumns[0].sortDescriptorPrototype = NSSortDescriptor(key: "Name", ascending: true)
        tableView.tableColumns[1].sortDescriptorPrototype = NSSortDescriptor(key: "Protocol", ascending: true)
        tableView.tableColumns[2].sortDescriptorPrototype = NSSortDescriptor(key: "Hostname", ascending: true)
        tableView.tableColumns[3].sortDescriptorPrototype = NSSortDescriptor(key: "Port", ascending: true)
        
        tableView.isEnabled = zid == nil ? false : true
        self.reloadData()
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first else {
            zLog.wtf("invalid sortDescriptor")
            return
        }
        sortKey = sortDescriptor.key
        ascending = sortDescriptor.ascending
        self.reloadData()
    }
    
    func reloadData() {
        if sortKey == "Name" {
            zid?.services.sort(by: {
                let a = $0.name ?? ""
                let b = $1.name ?? ""
                return ascending ? a < b : a > b
            })
        } else if sortKey == "Hostname" {
            zid?.services.sort(by: {
                let a = $0.dns?.hostname ?? ""
                let b = $1.dns?.hostname ?? ""
                return ascending ? a < b : a > b
            })
        } else if sortKey == "Port" {
            zid?.services.sort(by: {
                let a = $0.dns?.port ?? 0
                let b = $1.dns?.port ?? 0
                return ascending ? a < b : a > b
            })
        }
        tableView?.reloadData()
    }
    
    @objc func tableViewDoubleClick(_ sender:AnyObject) {
        guard tableView.selectedRow >= 0, let svc = zid?.services[tableView.selectedRow] else { return }
        
        if zid?.isEnabled ?? false {
            zLog.info("\n   name: \(svc.name ?? "")\n" +
                        "   status: \(svc.status?.status ?? .None) (\(DateFormatter().timeSince(svc.status?.lastUpdatedAt ?? 0)))\n" +
                        "   hostname: \(svc.dns?.hostname ?? "")\n" +
                        "   current ip: \(svc.dns?.interceptIp ?? "")\n" +
                        "   port: \(svc.dns?.port ?? 0)")
        } else {
            zLog.info("\(zid?.name ?? "") not enabled")
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
            text = "TCP"
            cellIdentifier = CellIdentifiers.ProtocolCell
        } else if tableColumn == tableView.tableColumns[2] {
            text = svc.dns?.hostname ?? "-"
            cellIdentifier = CellIdentifiers.HostnameCell
        } else if tableColumn == tableView.tableColumns[3] {
            text = String(svc.dns?.port ?? -1)
            cellIdentifier = CellIdentifiers.PortCell
        }
        
        if let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        
        return nil
    }
}
