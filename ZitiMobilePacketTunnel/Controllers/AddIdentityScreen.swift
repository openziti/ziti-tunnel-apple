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


class AddIdentityScreen: UIViewController, UIActivityItemSource, UIDocumentPickerDelegate, ScannerDelegate {
    
    let sc = ScannerViewController()
    var zidMgr = ZidMgr()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sc.delegate = self
    }
    
    func found(code: String?) {
        sc.dismiss(animated: true) {
            guard let code = code else { return }
            
            let secs = Int(NSDate().timeIntervalSince1970)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("QRScan\(secs).jwt")
            guard let data = code.data(using: .utf8) else {
                let alert = UIAlertController(
                    title:"Scan Error",
                    message: "Unable to decode scanned data",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Ok", comment: "Ok"),
                    style: .default,
                    handler: nil))
                DispatchQueue.main.async {
                    self.present(alert, animated: true, completion: nil)
                }
                return
            }
            
            do {
                try data.write(to: tempURL, options: .atomic)
                self.onNewUrl(tempURL)
            } catch {
                let alert = UIAlertController(
                    title:"Scan Error",
                    message: "Unable to store scanned data: \(error.localizedDescription)",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Ok", comment: "Ok"),
                    style: .default,
                    handler: nil))
                DispatchQueue.main.async {
                    self.present(alert, animated: true, completion: nil)
                }
            }
        }
    }
    
    func onNewUrl(_ url:URL) {
        DispatchQueue(label: "JwtLoader").async {
            do {
                try self.zidMgr.insertFromJWT(url, at: 0)
                DispatchQueue.main.async {
                    //self.tableView.reloadData()
                    //self.tableView.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)
                    // self.performSegue(withIdentifier: "IdentityDetailAddSeque", sender: self)
                    self.dismiss(animated: true, completion: nil)
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title:"Unable to add identity",
                        message: error.localizedDescription,
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
                    self.present(alert, animated: true, completion: nil)
                    NSLog("Unable to add identity: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @IBAction func QrAdd(_ sender: UITapGestureRecognizer) {
        present(sc, animated: true)
    }
    
    @IBAction func JwtAdd(_ sender: UITapGestureRecognizer) {
        let dp = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        dp.modalPresentationStyle = .formSheet
        dp.allowsMultipleSelection = false
        dp.delegate = self
        self.present(dp, animated: true, completion: nil)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        NSLog("picker cancelled")
    }
    
    @IBAction func dismissVC(_ sender: Any) {
         dismiss(animated: true, completion: nil)
    }
    
}
