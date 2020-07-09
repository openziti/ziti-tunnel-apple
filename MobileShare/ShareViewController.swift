//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import UIKit
import Social
import CZiti

@objc (ShareViewController)
class ShareViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet weak var fileLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var zid:ZitiIdentity?
    var url:URL?
    
    func showAlert(_ title:String, _ message:String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Default action"),
            style: .default, handler: completion))
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        
        Logger.initShared(Logger.APP_TAG)
        NSLog("MobileShare loaded")
        
        tableView.dataSource = self
        tableView.delegate = self
        
        let alertTitle = "Unable to import to Ziti"
        self.fileLabel.text = ""
        
        let attachments = (self.extensionContext?.inputItems.first as? NSExtensionItem)?.attachments ?? []
        if let provider = attachments.first {
            // Check if the content type is the same as we expected
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (data, error) in
                    guard error == nil else {
                        self?.showAlert(alertTitle, error!.localizedDescription) { _ in
                            self?.extensionContext?.cancelRequest(withError: error!)
                        }
                        return
                    }
                         
                    if let url = data as? URL {
                        let zidMgr = ZidMgr()
                        let zErr = zidMgr.loadZids()
                        if zErr != nil {
                            self?.showAlert(alertTitle, zErr!.localizedDescription) { _ in
                                self?.extensionContext?.cancelRequest(withError: zErr!)
                            }
                        } else {
                            do {
                                try zidMgr.insertFromJWT(url, at: 0)
                                DispatchQueue.main.async {
                                    self?.url = url
                                    self?.fileLabel.text = url.lastPathComponent
                                    self?.zid = zidMgr.zids.first
                                    self?.tableView.reloadData()
                                    self?.view.isHidden = false
                                }
                            } catch {
                                self?.showAlert(alertTitle, error.localizedDescription) { _ in
                                    self?.extensionContext?.cancelRequest(withError: error)
                                }
                            }
                        }
                    } else {
                        self?.showAlert(alertTitle, "Invalid URL") { _ in
                            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        }
                    }
                }
            } else {
                self.showAlert(alertTitle, "Unsupported content type identifier") { _ in
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            }
        } else {
            showAlert(alertTitle, "No attachements found") { _ in
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 3 : 1
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "IDENTITY_CELL", for: indexPath as IndexPath)
            if indexPath.row == 1 {
                cell.textLabel?.text = "Network"
                cell.detailTextLabel?.text = zid?.czid?.ztAPI ?? "-"
            } else if indexPath.row == 0 {
                cell.textLabel?.text = "Id"
                cell.detailTextLabel?.text = zid?.czid?.id ?? "-"
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Expires"
                cell.detailTextLabel?.text = zid != nil ? dateToString(zid!.expDate) : "-"
            }
            return cell
        } else {
            return tableView.dequeueReusableCell(withIdentifier: "ENROLL_CELL", for: indexPath as IndexPath)
        }
    }
    
    @IBAction func onEnrollButton(_ sender: Any) {
        guard let jwtFile = url?.path else {
            showAlert("Unable to enroll", "Invalid URL path")
            return
        }
        guard let zid = self.zid else {
            showAlert("Unable to enroll", "Invalid identity")
            return
        }
        
        // Ziti.enroll takes too long, needs to be done in background
        let spinner = SpinnerViewController()
        addChild(spinner)
        spinner.view.frame = view.frame
        view.addSubview(spinner.view)
        spinner.didMove(toParent: self)
        
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async {
                    // lose the spinner
                    spinner.willMove(toParent: nil)
                    spinner.view.removeFromSuperview()
                    spinner.removeFromParent()
                    
                    let zidMgr = ZidMgr()
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = zidMgr.zidStore.store(zid)
                        self.tableView.reloadData()
                        self.showAlert("Unable to enroll", zErr != nil ? zErr!.localizedDescription : "")
                        return
                    }
                    
                    if zid.czid == nil {
                        zid.czid = CZiti.ZitiIdentity(id: zidResp.id, ztAPI: zidResp.ztAPI)
                    }
                    zid.czid?.ca = zidResp.ca
                    if zidResp.name != nil {
                        zid.czid?.name = zidResp.name
                    }
                    
                    zid.enabled = true
                    zid.enrolled = true
                    _ = zidMgr.zidStore.store(zid)
                    self.tableView.reloadData()
                    self.showAlert("Enrolled",
                        "\(zidResp.name ?? self.url!.lastPathComponent) (\(zidResp.id)) successfully enrolled") { _ in
                        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    }
                }
            }
        }
    }
    
    @IBAction func onCancelButton(_ sender: Any) {
        let error = NSError(domain: "Ziti Mobile Edge Share", code: 0, userInfo: [NSLocalizedDescriptionKey: "User canceled request"])
        extensionContext?.cancelRequest(withError: error)
    }
    
    private func dateToString(_ date:Date) -> String {
        guard date != Date(timeIntervalSince1970: 0) else { return "unknown" }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .long, timeStyle: .long)
    }
}
