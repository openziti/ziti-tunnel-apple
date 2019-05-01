//
//  LogsViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/30/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import UIKit

class LogsTableViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print("\(indexPath)")
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
