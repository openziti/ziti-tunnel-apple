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
import CZiti

class LogsTableViewController: UITableViewController {

    @IBOutlet weak var logTlsuvSwitch: UISwitch!
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    @IBAction func logTlsuvSwitchChanged(_ sender: Any) {
        TunnelMgr.shared.tlsuvLoggingEnabled = logTlsuvSwitch.isOn
        TunnelMgr.shared.updateLogLevel(ZitiLog.getLogLevel())
    }
    
    override func viewDidAppear(_ animated: Bool) {
        logTlsuvSwitch.isOn = TunnelMgr.shared.tlsuvLoggingEnabled
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            if let vc = UIStoryboard.init(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "LOG_VC") as? LogViewController {
                vc.title = "Packet Tunnel Log"
                vc.tag = Logger.TUN_TAG
                navigationController?.pushViewController(vc, animated: true)
            }
        } else if indexPath.section == 1 {
            if let vc = UIStoryboard.init(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "LOG_VC") as? LogViewController {
                vc.title = "Application Log"
                vc.tag = Logger.APP_TAG
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
