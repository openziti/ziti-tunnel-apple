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
import MessageUI
import CZiti


class IdentityDetailScreen: UIViewController, UIActivityItemSource {
    
    @IBOutlet weak var IdName: UITextView!
    @IBOutlet weak var IdNetwork: UITextView!
    @IBOutlet weak var IdStatus: UITextView!
    @IBOutlet weak var IdEnrollment: UITextView!
    @IBOutlet weak var IdVersion: UITextView!
    @IBOutlet weak var IdServiceCount: UILabel!
    @IBOutlet weak var ServiceList: UIScrollView!
    @IBOutlet weak var EnrollButton: UIButton!
    
    var zid:ZitiIdentity?
    var zidMgr:ZidMgr?
    var tunnelMgr:TunnelMgr?
    var dash:DashboardScreen?
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @IBAction func dismissVC(_ sender: Any) {
         dismiss(animated: true, completion: nil)
    }
    
    @IBAction func ForgetAction(_ sender: UITapGestureRecognizer) {
        let alert = UIAlertController(
            title:"Are you sure?",
            message: "Deleting identity \(zid?.name ?? "") cannot be undone.",
            preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Default action"),
            style: .default,
            handler: { _ in
                if let zid = self.zid {
                    _ = self.zidMgr?.zidStore.remove(zid)
                    if let indx = self.zidMgr?.zids.firstIndex(of: zid) {
                        self.zidMgr?.zids.remove(at: indx)
                    }
                }
                self.dash?.reloadList();
                self.dismiss(animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel))
        present(alert, animated: true, completion: nil)
    }
    
    override func viewDidLoad() {
        IdName.text = zid?.name;
        IdNetwork.text = zid?.czid?.ztAPI;
        IdVersion.text = zid?.controllerVersion ?? "unknown";
        IdEnrollment.text = zid?.enrollmentStatus.rawValue;
        IdServiceCount.text = "\(String(describing: zid?.services.count)) Services";
        
        let cs = zid?.edgeStatus ?? ZitiIdentity.EdgeStatus(0, status:.None)
        var csStr = ""
        if zid?.isEnrolled ?? false == false {
            csStr = "None"
            EnrollButton.isHidden = false;
        } else if cs.status == .PartiallyAvailable {
            csStr = "Partially Available"
        } else {
            csStr = cs.status.rawValue
        }
        for view in ServiceList.subviews {
            view.removeFromSuperview();
        }
        if zid?.isEnrolled ?? false {
            var index = 0;
            var rowHeight = 30;
            guard let zid = self.zid else { return }
            for service in zid.services {
                let serviceName = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 20));
                let serviceUrl = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 20));
                
                serviceName.text = service.name;
                serviceUrl.text = "\(service.dns?.hostname ?? ""):\(service.dns?.port ?? -1)";
                
                serviceName.font = UIFont(name: "Open Sans", size: 12);
                serviceName.textColor = UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00);
                serviceUrl.font = UIFont(name: "Open Sans", size: 11);
                serviceUrl.textColor = UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.80);
                
                serviceName.isEditable = false;
                serviceName.isScrollEnabled = false;
                serviceUrl.isEditable = false;
                serviceUrl.isScrollEnabled = false;
                serviceUrl.textAlignment = .right;
                
                serviceName.backgroundColor = UIColor.clear;
                serviceUrl.backgroundColor = UIColor.clear;
                
                serviceName.widthAnchor.constraint(equalToConstant: self.view.frame.width).isActive = true
                serviceName.heightAnchor.constraint(equalToConstant: CGFloat(rowHeight)).isActive = true
                serviceUrl.widthAnchor.constraint(equalToConstant: self.view.frame.width).isActive = true
                serviceUrl.heightAnchor.constraint(equalToConstant: CGFloat(rowHeight)).isActive = true
                
                let stack = UIStackView(arrangedSubviews: [serviceName, serviceUrl]);
                
                stack.distribution = .fill;
                stack.alignment = .leading;
                stack.spacing = 5;
                stack.axis = .horizontal;
                stack.frame = CGRect(x: 20, y: CGFloat(index*rowHeight), width: view.frame.size.width-CGFloat(rowHeight), height: 30);

                ServiceList.addSubview(stack);
                index = index + 1;
            }
            ServiceList.contentSize.height = CGFloat(index*rowHeight);
    
        }
        csStr += " (as of \(DateFormatter().timeSince(cs.lastContactAt)))"
        IdStatus.text = csStr;
    }
    
    @IBAction func DoEnrollment(_ sender: UITapGestureRecognizer) {
        guard let zid = self.zid else { return }
        guard let presentedItemURL = self.zidMgr?.zidStore.presentedItemURL else {
            let alert = UIAlertController(
                title:"Unable to enroll \(zid.name)",
                message: "Unable to access group container",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("OK", comment: "Default action"),
                style: .default))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        let url = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false)
        let jwtFile = url.path
        
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
                    
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = self.zidMgr?.zidStore.store(zid)
                        
                        let alert = UIAlertController(
                            title:"Unable to enroll \(zid.name)",
                            message: zErr != nil ? zErr!.localizedDescription : "",
                            preferredStyle: .alert)
                        
                        alert.addAction(UIAlertAction(
                            title: NSLocalizedString("OK", comment: "Default action"),
                            style: .default))
                        self.present(alert, animated: true, completion: nil)
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
                    _ = self.zidMgr?.zidStore.store(zid)
                    self.tunnelMgr?.restartTunnel()
                    self.dash?.reloadList();
                }
            }
        }
    }
    
    func onEnabledValueChanged(_ enabled:Bool) {
        if let zid = self.zid {
            zid.enabled = enabled
            _ = zidMgr?.zidStore.store(zid)
            tunnelMgr?.restartTunnel()
            self.dash?.reloadList();
        }
    }
    
}
