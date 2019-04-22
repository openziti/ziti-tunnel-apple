//
//  AboutViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/22/19.
//  Copyright © 2019 David Hart. All rights reserved.
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
            var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown version"
            if let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                appVersion += " (\(appBuild))"
            }
            return "Version \(appVersion)"
        }
        return nil
    }

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
