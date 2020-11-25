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
import SafariServices
import MessageUI

class DashboardScreen: UIViewController, UIActivityItemSource, MFMailComposeViewControllerDelegate, ZitiIdentityStoreDelegate {

        
    var isMenuOpen = false
    var originalDashTransform:CGAffineTransform!
    var originalBgTransform:CGAffineTransform!
    var tunnelMgr = TunnelMgr.shared
    var zidMgr = ZidMgr()
    
    @IBOutlet weak var ConnectButton: UIImageView!
    @IBOutlet weak var ConnectedButton: UIView!
    @IBOutlet weak var Dashboard: UIStackView!
    @IBOutlet weak var Background: UIView!
    @IBOutlet weak var IdentityList: UIStackView!
    @IBOutlet weak var IdentityItem: IdentityRenderer!
    
    
    @IBAction func DoConnect(_ sender: UITapGestureRecognizer) {
        ConnectButton.isHidden = true;
        ConnectedButton.isHidden = false;
        do {
            try tunnelMgr.startTunnel()
        } catch {
            let alert = UIAlertController(
                title:"Ziti Connect Error",
                message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
        }
    }
    
    @IBAction func DoDisconnect(_ sender: UITapGestureRecognizer) {
        ConnectButton.isHidden = false;
        ConnectedButton.isHidden = true;
        tunnelMgr.stopTunnel()
    }
    
    @IBAction func CloseMenuGesture(_ sender: UITapGestureRecognizer) {
        if (self.isMenuOpen) {
            self.isMenuOpen = !self.isMenuOpen
            
            self.Background.layer.cornerRadius = 0
            self.Background.layer.masksToBounds = false
            
            UIView.animate(withDuration: 0.3, animations: {
                self.Dashboard.transform = self.originalDashTransform
                self.Background.transform = self.originalBgTransform
            })
        }
    }
    
    @IBAction func HideIfOpen(_ sender: UITapGestureRecognizer) {
        if (self.isMenuOpen) {
            self.isMenuOpen = !self.isMenuOpen
            
            self.Background.layer.cornerRadius = 0
            self.Background.layer.masksToBounds = false
            
            UIView.animate(withDuration: 0.3, animations: {
                self.Dashboard.transform = self.originalDashTransform
                self.Background.transform = self.originalBgTransform
            })
        }
    }
    
    @IBAction func ShowMenu(_ sender: UITapGestureRecognizer) {
        if (self.isMenuOpen) {
            self.isMenuOpen = !self.isMenuOpen
            
            self.Background.layer.cornerRadius = 0
            self.Background.layer.masksToBounds = false
            
            UIView.animate(withDuration: 0.3, animations: {
                self.Dashboard.transform = self.originalDashTransform
                self.Background.transform = self.originalBgTransform
            })
        } else {
            self.isMenuOpen = !self.isMenuOpen
            
            self.originalDashTransform = self.Dashboard.transform
            let scaledTransform = originalDashTransform.scaledBy(x: 0.9, y: 0.9)
            let scaledAndTranslatedTransform = scaledTransform.translatedBy(x: 260, y: -20.0)
            
            self.originalBgTransform = self.Background.transform
            let scaledBgTransform = originalBgTransform.scaledBy(x: 0.9, y: 0.9)
            let scaledBgAndTranslatedTransform = scaledBgTransform.translatedBy(x: 260, y: -20.0)
        
            self.Background.layer.cornerRadius = 20
            self.Background.layer.masksToBounds = true
            
            UIView.animate(withDuration: 0.3, animations: {
                self.Dashboard.transform = scaledAndTranslatedTransform
                self.Background.transform = scaledBgAndTranslatedTransform
            })
        }
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @objc func GoToDetails(gesture : UITapGestureRecognizer) {
        let v = gesture.view!;
        let tag = v.tag;
        let storyBoard : UIStoryboard = UIStoryboard(name: "MainUI", bundle:nil);
        let idDetails = storyBoard.instantiateViewController(withIdentifier: "IdentityDetail") as! IdentityDetailScreen;
        idDetails.zid = zidMgr.zids[tag];
        self.present(idDetails, animated:true, completion:nil);
        
    }
    
    func reloadList() {
        for view in IdentityList.arrangedSubviews {
            view.removeFromSuperview();
        }
        var index = 0;
        for identity in zidMgr.zids {
            let idName = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 40));
            let idServer = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 40));
            let idServiceCount = UILabel(frame: CGRect(x: 0, y: 0, width: 40, height: 40));
            
            let isConnectedLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 40));
            let serviceLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 40));
            
            let arrowImage = UIImage(named: "next");
            let arrowView = UIImageView(image: arrowImage);
            arrowView.frame = CGRect(x: 0, y: 0, width: 20, height: 60);
            let toggler = UISwitch(frame: CGRect(x: 0, y: 0, width: 30, height: 40));
            
            idName.text = identity.name;
            idServer.text = identity.czid?.ztAPI;
            idServiceCount.text = String(identity.services.count);
            serviceLabel.text = "services";
            if (identity.enabled ?? false) {
                isConnectedLabel.text = "connected";
            } else {
                isConnectedLabel.text = "disconnected";
            }
            
            idName.font = UIFont(name: "Open Sans", size: 14);
            idServiceCount.font = UIFont(name: "Open Sans", size: 14);
            serviceLabel.font = UIFont(name: "Open Sans", size: 10);
            serviceLabel.textColor = UIColor(named: "Light Gray Color");
            isConnectedLabel.font = UIFont(name: "Open Sans", size: 10);
            isConnectedLabel.textColor = UIColor(named: "Light Gray Color");
            idServer.font = UIFont(name: "Open Sans", size: 10);
            idServer.textColor = UIColor(named: "Light Gray Color");
            
            let col1 = UIStackView(arrangedSubviews: [toggler, isConnectedLabel]);
            let col2 = UIStackView(arrangedSubviews: [idName, idServer]);
            let col3 = UIStackView(arrangedSubviews: [idServiceCount, serviceLabel]);
            let col4 = UIStackView(arrangedSubviews: [arrowView]);
            
            col1.distribution = .fillEqually;
            col1.alignment = .fill;
            col1.spacing = 0;
            col1.axis = .vertical;
            col1.frame = CGRect(x: 0, y: 0, width: 150, height: 60);
            col1.translatesAutoresizingMaskIntoConstraints = false;
            
            col2.distribution = .fillEqually;
            col2.alignment = .fill;
            col2.spacing = 0;
            col2.axis = .vertical;
            col2.translatesAutoresizingMaskIntoConstraints = false;
            col2.isUserInteractionEnabled = true;
            col2.tag = index;
            col2.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.GoToDetails(gesture:))));
            
            col3.distribution = .fillEqually;
            col3.alignment = .center;
            col3.spacing = 0;
            col3.axis = .vertical;
            col3.frame = CGRect(x: 10, y: 10, width: 60, height: 60);
            col3.translatesAutoresizingMaskIntoConstraints = false;
            
            col4.distribution = .fillEqually;
            col4.alignment = .fill;
            col4.spacing = 0;
            col4.axis = .vertical;
            col4.frame = CGRect(x: 0, y: 0, width: 20, height: 60);
            col4.translatesAutoresizingMaskIntoConstraints = false;
            
            let renderer = UIStackView(arrangedSubviews: [col1,col2,col3,col4]);
            renderer.axis = .horizontal;
            renderer.distribution = .fill;
            renderer.alignment = .fill;
            renderer.spacing = 8;
            renderer.frame = CGRect(x: 0, y: CGFloat(index*60), width: view.frame.size.width, height: 60)
            
            IdentityList.addSubview(renderer);
            index = index + 1;
        }
    }
    
    // Copied From Daves Controller
    
    
    
    func onRemovedId(_ idString: String) {
        DispatchQueue.main.async {
            //if let match = self.zidMgr.zids.first(where: { $0.id == idString }) {
                // shouldn't happend unless somebody deletes the file.
            NSLog("\(idString) REMOVED");
            _ = self.zidMgr.loadZids();
            self.reloadList();
            self.tunnelMgr.restartTunnel();
           // }
        }
    }
    
    func onNewUrl(_ url:URL) {
        DispatchQueue(label: "JwtLoader").async {
            do {
                try self.zidMgr.insertFromJWT(url, at: 0)
                DispatchQueue.main.async {
                    // Send to details
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
    
    @objc func onNewUrlNotification(_ notification: NSNotification) {
        if let dict = notification.userInfo as NSDictionary?, let url = dict["url"] as? URL {
            onNewUrl(url)
        }
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        DispatchQueue.main.async {
            if let match = self.zidMgr.zids.first(where: { $0.id == zid.id }) {
                NSLog("\(zid.name):\(zid.id) CHANGED")
                
                // TUN will disable if unable to start for zid
                match.edgeStatus = zid.edgeStatus
                match.enabled = zid.enabled
                
                // always take new service from tunneler...
                match.services = zid.services
                match.czid?.name = zid.name
                match.controllerVersion = zid.controllerVersion
            } else {
                // new one.  generally zids are only added by this app (so will be matched above).
                // But possible somebody could load one manually or some day via MDM or somesuch
                NSLog("\(zid.name):\(zid.id) NEW")
                self.zidMgr.zids.insert(zid, at:0)
                
                DispatchQueue.main.async {
                    // Show Details
                }
                self.tunnelMgr.restartTunnel()
            }
            self.reloadList();
            
            let needsRestart = zid.services.filter {
                if let status = $0.status, let needsRestart = status.needsRestart {
                    return needsRestart
                }
                return false
            }
            print("--- needsRestart = \(needsRestart.count)")
            if needsRestart.count > 0 {
                self.tunnelMgr.restartTunnel()
            }
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // watch for changes to the zids
        zidMgr.zidStore.delegate = self
        
        // watch for new URLs
        NotificationCenter.default.addObserver(self, selector: #selector(self.onNewUrlNotification(_:)), name: NSNotification.Name(rawValue: "NewURL"), object: nil)


        // init the manager
        tunnelMgr.loadFromPreferences(TableViewController.providerBundleIdentifier) { tpm, error in
            DispatchQueue.main.async {
                self.reloadList();
            }
        }
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            NSLog(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        self.reloadList();
    }
    
    func deviceName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        if modelCode != nil {
            return String(cString: modelCode!, encoding: .utf8) ?? ""
        } else {
            return ""
        }
    }
    
    @IBAction func ShowFeedback(_ sender: UITapGestureRecognizer) {
        let supportEmail = Bundle.main.infoDictionary?["ZitiSupportEmail"] as? String ?? ""
        let supportSubj = Bundle.main.infoDictionary?["ZitiSupportSubject"] as? String ?? ""
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            //mail.mailComposeDelegate = self
            mail.setSubject(supportSubj)
            mail.setToRecipients([supportEmail])
            mail.setMessageBody("\n\n\nVersion: \(Version.str)\nOS \(Version.osVersion)\nDevice: \(deviceName())", isHTML: false)
            if let logger = Logger.shared {
                if let url = logger.currLog(forTag: Logger.TUN_TAG), let data = try? Data(contentsOf: url) {
                    mail.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
                }
                if let url = logger.currLog(forTag: Logger.APP_TAG), let data = try? Data(contentsOf: url) {
                    mail.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
                }
            }
            self.present(mail, animated: true)
        } else {
            NSLog("Mail view controller not available")
            let alert = UIAlertController(
                title:"Mail view not available",
                message: "Please email \(supportEmail) for assistance",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction func ShowSupport(_ sender: UITapGestureRecognizer) {
        let url = URL (string: "https://openziti.discourse.group")!
        UIApplication.shared.open (url)
    }
    
    
}
