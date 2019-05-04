//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Cocoa

class ServicesViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    
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
        
        tableView.isEnabled = zid == nil ? false : true
        tableView.reloadData()
    }
    
    @objc func tableViewDoubleClick(_ sender:AnyObject) {
        guard tableView.selectedRow >= 0, let svc = zid?.services?[tableView.selectedRow] else { return }
        
        print("\nTODO: modal view, button to clear net session and restart")
        print("name: \(svc.name ?? "")")
        print("status: \(svc.status?.status ?? .None) (\(DateFormatter().timeSince(svc.status?.lastUpdatedAt ?? 0)))")
        print("hostname: \(svc.dns?.hostname ?? "")")
        print("current ip: \(svc.dns?.interceptIp ?? "")")
        print("port: \(svc.dns?.port ?? 0)")
        
        if let gws = svc.networkSession?.gateways {
            gws.forEach { gw in
                print("gateway: \(gw.name ?? ""): \(gw.hostname ?? "")")
                gw.urls?.forEach { url in
                    print("   \(url.key): \(url.value)")
                }
            }
        }
    }
    
    override var representedObject: Any? {
        didSet {
            tableView?.isEnabled = zid == nil ? false : true
            
            let selectedRow = tableView?.selectedRow ?? 0
            tableView?.reloadData()
            tableView?.selectRowIndexes([selectedRow], byExtendingSelection: false)
        }
    }
}

extension ServicesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return zid?.services?.count ?? 0
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
        guard let svc = zid?.services?[row] else {
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
