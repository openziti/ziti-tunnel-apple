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
import SafariServices

class AboutViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ABOUT_CELL", for: indexPath)

        if indexPath.row == 0 {
            cell.textLabel?.text = "Privacy Policy"
        } else if indexPath.row == 1 {
            cell.textLabel?.text = "Terms of Service"
        } else if indexPath.row == 2 {
            cell.textLabel?.text = "Third Policy Licences"
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            if let url = URL(string: "https://netfoundry.io/privacy-policy/") {
                let vc = SFSafariViewController(url: url)
                present(vc, animated: true)
            }
        } else if indexPath.row == 1 {
            if let url = URL(string: "https://netfoundry.io/terms/") {
                let vc = SFSafariViewController(url: url)
                present(vc, animated: true)
            }
        } else if indexPath.row == 2 {
            if let vc = UIStoryboard.init(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "NOTICES_VC") as? NoticesViewController {
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Version \(Version.str)"
        }
        return nil
    }
}
