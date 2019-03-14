//
//  ServicesViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/21/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Cocoa

class ServicesViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    
    var zid:ZitiIdentity? {
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
        
        tableView.isEnabled = zid == nil ? false : true
        tableView.reloadData()
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
