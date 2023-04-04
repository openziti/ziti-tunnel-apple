//
// Copyright NetFoundry, Inc.
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

class ServiceViewController: UITableViewController {
    
    var svc:ZitiService?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        var nSections = 1
        if svc?.status?.needsRestart ?? false {
            nSections += 1
        }
        return nSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var nRows = 1
        if section == 0 {
            nRows = 6
        }
        return nRows
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SERVICE_TABLE_CELL", for: indexPath)

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Name"
                cell.detailTextLabel?.text = svc?.name
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Service Type"
                cell.detailTextLabel?.text = svc?.serviceType?.rawValue ?? ZitiService.ServiceType.DIAL.rawValue
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Protocols"
                cell.detailTextLabel?.text = svc?.protocols
            } else if indexPath.row == 3 {
                cell.textLabel?.text = "Addresses"
                cell.detailTextLabel?.text = svc?.addresses
            } else if indexPath.row == 4 {
                cell.textLabel?.text = "Ports"
                cell.detailTextLabel?.text = svc?.portRanges
            } else if indexPath.row == 5 {
                cell.textLabel?.text = "Posture Checks"
                
                var details = ""
                if let svc = svc {
                    if svc.postureChecksPassing() {
                        details = "PASS"
                    } else {
                        details = "FAIL"
                        let fails = svc.failingPostureChecks()
                        if fails.count > 0 {
                            details += " (\(fails.joined(separator: ",")))"
                        }
                    }
                }
                cell.detailTextLabel?.text = details
            }
        } else if indexPath.section == 1 {
            cell.textLabel?.text = "Restart may be required to access service"
            cell.detailTextLabel?.text = ""
            cell.imageView?.image = UIImage(systemName:"exclamationmark.triangle.fill")
        }
        return cell
    }
}
