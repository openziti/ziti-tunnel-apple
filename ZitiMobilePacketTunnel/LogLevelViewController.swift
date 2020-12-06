//
// Copyright 2020 NetFoundry, Inc.
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
import CZiti

class LogLevelViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let lvl = Int(ZitiLog.getLogLevel().rawValue)
        let ip = IndexPath(row: lvl, section: 0)
        tableView.selectRow(at: ip, animated: true, scrollPosition: .none)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        zLog.info("selected row at \(indexPath.row)")
        let lvl = ZitiLog.LogLevel(rawValue: Int32(indexPath.row)) ?? ZitiLog.LogLevel.INFO
        TunnelMgr.shared.updateLogLevel(lvl)
    }
}
