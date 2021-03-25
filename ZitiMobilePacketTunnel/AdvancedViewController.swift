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

import UIKit
import NetworkExtension

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
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell:UITableViewCell
        
        // Prob need two Identifiers to make seque act the way I want..
        if indexPath.section == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: "TUNNEL_CONFIG_CELL", for: indexPath)
        } else if indexPath.section == 1 {
            cell = tableView.dequeueReusableCell(withIdentifier: "LOGS_CELL", for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "SNAPSHOT_CELL", for: indexPath)
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
        } else if section == 2 {
            return "Snapshot of current connectivity state"
        }
        return nil
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let tsvc = segue.destination as? TunnelSettingsViewController {
            tsvc.tvc = tvc
        } else if let svc = segue.destination as? SnapshotViewController {
            do {
                try (TunnelMgr.shared.tpm?.connection as? NETunnelProviderSession)?.sendProviderMessage("dump".data(using: .utf8)!) { resp in
                    if let resp = resp, var str = String(data: resp, encoding: .utf8) {
                        zLog.info(str)
                        if str == "" { str = "No connection data available" }
                        svc.textView.text = str
                    }
                }
            } catch {
                zLog.error("Unable to send provider message: \(error)")
            }
        }
    }
}
