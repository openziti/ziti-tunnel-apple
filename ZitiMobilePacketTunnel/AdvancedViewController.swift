//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import UIKit

class AdvancedViewController: UITableViewController {
    
    weak var tvc:TableViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell
        
        // Prob need two Identifiers to make seque act the way I want..
        if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "TUNNEL_CONFIG_CELL", for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "LOGS_CELL", for: indexPath)
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return ""
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Advanced tunnel settings that will impact tunnel availability and performace."
        } else if section == 1 {
            return "Diagnostic logs that help us debug if you are having problems."
        }
        return nil
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let tsvc = segue.destination as? TunnelSettingsViewController {
            print("setting tvc in TunnelSettingsViewController")
            tsvc.tvc = tvc
        }
    }
}
