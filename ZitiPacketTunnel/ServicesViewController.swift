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
    
    var zId:ZitiIdentity? {
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
        
        tableView.isEnabled = zId == nil ? false : true
    }
    
    override var representedObject: Any? {
        didSet {
            
        }
    }
    
    func updateServices(_ zId:ZitiIdentity?) {
        print("UPDATE SERVICES..")
        tableView.isEnabled = zId == nil ? false : true
    }
}

extension ServicesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return 0
    }
}

extension ServicesViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return nil
    }
}
