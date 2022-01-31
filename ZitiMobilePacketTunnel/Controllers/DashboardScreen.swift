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
    @IBOutlet weak var TimerLabel: UILabel!
    var timer = Timer();
    var timeLaunched:Int = 0;
    
    @IBOutlet weak var IdList: UIStackView!
    @IBOutlet weak var ConnectButton: UIImageView!
    @IBOutlet weak var ConnectedButton: UIView!
    @IBOutlet weak var Dashboard: UIStackView!
    @IBOutlet weak var Background: UIView!
    @IBOutlet weak var IdentityList: UIScrollView!
    @IBOutlet weak var IdentityItem: IdentityRenderer!
    @IBOutlet weak var IdView: UIView!
    
    @objc func UpdateTimer() {
        let formatter = DateComponentsFormatter();
        formatter.allowedUnits = [.hour, .minute, .second];
        formatter.unitsStyle = .positional;
        formatter.zeroFormattingBehavior = .pad;

        TimerLabel.text = formatter.string(from: TimeInterval(timeLaunched))!;
        timeLaunched += 1;
    }
    
    func Connect() {
        TimerLabel.text = "00:00.00";
        ConnectButton.isHidden = true;
        ConnectedButton.isHidden = false;
        do {
            try tunnelMgr.startTunnel()
            timeLaunched = 1;
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
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
    
    @IBAction func DoConnect(_ sender: UITapGestureRecognizer) {
        self.Connect();
    }
    
    @IBAction func DoDisconnect(_ sender: UITapGestureRecognizer) {
        TimerLabel.text = "00:00.00";
        timer.invalidate();
        ConnectButton.isHidden = false;
        ConnectedButton.isHidden = true;
        tunnelMgr.stopTunnel();
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
    
    @IBAction func ShowAddIdentity(_ sender: UITapGestureRecognizer) {
        let storyBoard : UIStoryboard = UIStoryboard(name: "MainUI", bundle:nil);
        let screen = storyBoard.instantiateViewController(withIdentifier: "AddIdentity") as! AddIdentityScreen;
        screen.zidMgr = zidMgr;
        screen.dash = self;
        screen.modalPresentationStyle = .fullScreen;
        self.present(screen, animated:true, completion:nil);
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @IBOutlet weak var MainTitle: UILabel!
    
    @objc func GoToDetails(gesture : UITapGestureRecognizer) {
        let v = gesture.view!;
        let tag = v.tag;
        let storyBoard : UIStoryboard = UIStoryboard(name: "MainUI", bundle:nil);
        let idDetails = storyBoard.instantiateViewController(withIdentifier: "IdentityDetail") as! IdentityDetailScreen;
        idDetails.zid = zidMgr.zids[tag];
        idDetails.zidMgr = zidMgr;
        idDetails.tunnelMgr = tunnelMgr;
        idDetails.modalPresentationStyle = .fullScreen;
        self.present(idDetails, animated:true, completion:nil);
        
    }
    
    @objc func SwapToggle(gesture : UITapGestureRecognizer) {
        let v = gesture.view!;
        let tag = v.tag;
        let zid = zidMgr.zids[tag];
        zid.enabled = !zid.enabled!;
    }
    
    @IBAction func switchValueDidChange(sender:UISwitch!) {
        let tag = sender.tag;
        let zid = zidMgr.zids[tag];
        zid.enabled = sender.isOn;
        _ = self.zidMgr.zidStore.store(zid);
        self.tunnelMgr.restartTunnel();
    }
    
    func reloadList() {
        //if IdView.subviews != nil {
            for view in IdentityList.subviews {
                view.removeFromSuperview();
            }
        //}
        var index = 0;
        
        for identity in zidMgr.zids {
            let identityItem = IdentityListitem();
            identityItem.setIdentity(identity: identity, vc: self)
            identityItem.frame = CGRect(x: 0, y: CGFloat(index*62), width: 340, height: 60);
            IdList.addArrangedSubview(identityItem);
            index = index + 1;
        }
        IdentityList.contentSize.height = CGFloat(index*72);
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
                // Load previous identities
                if let err = self.zidMgr.loadZids() {
                    NSLog(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
                }
                if (self.tunnelMgr.status == .disconnected) {
                    self.Connect();
                } else {
                    self.reloadList();
                }
            }
        }
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
    
    
}
