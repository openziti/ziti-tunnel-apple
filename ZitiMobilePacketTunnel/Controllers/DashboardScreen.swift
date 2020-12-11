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
    
    @IBOutlet weak var ConnectButton: UIImageView!
    @IBOutlet weak var ConnectedButton: UIView!
    @IBOutlet weak var Dashboard: UIStackView!
    @IBOutlet weak var Background: UIView!
    @IBOutlet weak var IdentityList: UIScrollView!
    @IBOutlet weak var IdentityItem: IdentityRenderer!
    
    @objc func UpdateTimer() {
        let formatter = DateComponentsFormatter();
        formatter.allowedUnits = [.hour, .minute, .second];
        formatter.unitsStyle = .positional;
        formatter.zeroFormattingBehavior = .pad;

        TimerLabel.text = formatter.string(from: TimeInterval(timeLaunched))!;
        timeLaunched += 1;
    }
    
    @IBAction func DoConnect(_ sender: UITapGestureRecognizer) {
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
    
    @IBAction func DoDisconnect(_ sender: UITapGestureRecognizer) {
        TimerLabel.text = "00:00.00";
        timer.invalidate();
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
    
    @IBOutlet weak var MainTitle: UILabel!
    
    @objc func GoToDetails(gesture : UITapGestureRecognizer) {
        let v = gesture.view!;
        let tag = v.tag;
        let storyBoard : UIStoryboard = UIStoryboard(name: "MainUI", bundle:nil);
        let idDetails = storyBoard.instantiateViewController(withIdentifier: "IdentityDetail") as! IdentityDetailScreen;
        idDetails.zid = zidMgr.zids[tag];
        idDetails.zidMgr = zidMgr;
        idDetails.tunnelMgr = tunnelMgr;
        self.present(idDetails, animated:true, completion:nil);
        
    }
    
    @objc func SwapToggle(gesture : UITapGestureRecognizer) {
        let v = gesture.view!;
        let tag = v.tag;
        let zid = zidMgr.zids[tag];
        zid.enabled = !zid.enabled!;
    }
    
    func switchValueDidChange(sender:UISwitch!)
    {
        if (sender.isOn == true){
            print("on")
        }
        else{
            print("off")
        }
    }
    
    func reloadList() {
        for view in IdentityList.subviews {
            view.removeFromSuperview();
        }
        var index = 0;
        for identity in zidMgr.zids {
            
            
            // First Column of Identity Item Renderer
            let toggler = UISwitch(frame: CGRect(x: 0, y: 0, width: 75, height: 30));
            let connectLabel = UILabel();
            
            connectLabel.frame.size.height = 20;
            connectLabel.font = UIFont(name: "Open Sans", size: 10);
            connectLabel.textColor = UIColor(named: "Light Gray Color");
            
            toggler.isEnabled = identity.isEnrolled;
            toggler.isOn = identity.isEnabled;
            toggler.isUserInteractionEnabled = true;
            toggler.tag = index;
            toggler.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.GoToDetails(gesture:))));
            //toggler.addTarget(self, action: Selector(("switchValueDidChange:")), for: UIControl.Event.valueChanged);
            
            if (identity.isEnrolled) {
                if (identity.isEnabled) {
                    connectLabel.text = "connected";
                } else {
                    connectLabel.text = "disconnected";
                }
            } else {
                connectLabel.text = "not enrolled";
            }
            
            
            let leadLabel1 = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 5));
            leadLabel1.text = " ";
            
            let col1 = UIStackView(arrangedSubviews: [leadLabel1,toggler,connectLabel]);
            
            col1.frame.size.width = 75;
            col1.distribution = .fillProportionally;
            col1.alignment = .center;
            col1.spacing = 0;
            col1.axis = .vertical;
            
            
            // Label Column of Identity Item Renderer
            let idName = UILabel();
            
            idName.font = UIFont(name: "Open Sans", size: 22);
            idName.textColor = UIColor(named: "White");
            
            idName.text = String(String(identity.name).prefix(10));
            
            
            let idServer = UILabel();
            idServer.font = UIFont(name: "Open Sans", size: 10);
            idServer.textColor = UIColor(named: "Light Gray Color");
            idServer.frame.size.height = 20;
            idServer.text = identity.czid?.ztAPI;
            
            let leadLabel2 = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 5));
            leadLabel2.text = " ";
            
            let col2 = UIStackView(arrangedSubviews: [leadLabel2, idName, idServer]);
            col2.distribution = .fillProportionally;
            col2.alignment = .leading;
            col2.spacing = 0;
            col2.frame.size.width = 100;
            col2.axis = .vertical;
            col2.isUserInteractionEnabled = true;
            col2.tag = index;
            col2.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.GoToDetails(gesture:))));
            
            
            // Count column for the item renderer
            
            let serviceCountFrame = UIView();
            let circlePath = UIBezierPath(arcCenter: CGPoint(x: 0, y: 15), radius: CGFloat(15), startAngle: CGFloat(0), endAngle: CGFloat(Double.pi * 2), clockwise: true);
            let shapeLayer = CAShapeLayer();
            serviceCountFrame.frame = CGRect(x: 0, y: 0, width: 50, height: 40)
            shapeLayer.path = circlePath.cgPath;
            shapeLayer.fillColor = UIColor(named: "PrimaryColor")?.cgColor;
            
            let idServiceCount = UILabel();
            idServiceCount.textAlignment = .center;
            idServiceCount.font = UIFont(name: "Open Sans", size: 22);
            idServiceCount.textColor = UIColor(named: "White");
            idServiceCount.text = String(identity.services.count);
            
            let serviceLabel = UILabel();
            serviceLabel.textAlignment = .center;
            serviceLabel.text = "services";
            serviceLabel.frame.size.height = 20;
            serviceLabel.font = UIFont(name: "Open Sans", size: 10);
            serviceLabel.textColor = UIColor(named: "Light Gray Color");
            
            //serviceCountFrame.layer.addSublayer(shapeLayer);
            serviceCountFrame.addSubview(idServiceCount);
            
            
            let leadLabel3 = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 5));
            leadLabel3.text = " ";
            
            let col3 = UIStackView(arrangedSubviews: [leadLabel3, idServiceCount, serviceLabel]);
            col3.frame.size.width = 50;
            col3.distribution = .fillProportionally;
            col3.alignment = .center;
            col3.spacing = 0;
            col3.axis = .vertical;
            col3.isUserInteractionEnabled = true;
            col3.tag = index;
            col3.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.GoToDetails(gesture:))));
            
            
            
            // Arrow image for Item Renderer
            
            let arrowImage = UIImage(named: "next");
            let arrowView = UIImageView();
            arrowView.frame = CGRect(x: 10, y: 10, width: 10, height: 10);
            arrowView.contentMode = .scaleAspectFit;
            arrowView.image = arrowImage;
            
            // These are simple margins because iOS keeps ignoring margin settings
            let leadLabel4 = UILabel(frame: CGRect(x: 0, y: 0, width: 30, height: 10));
            leadLabel4.text = " ";
            
            
            let col4 = UIStackView(arrangedSubviews: [leadLabel4,arrowView]);
            col4.distribution = .fillProportionally;
            col4.alignment = .center;
            col4.spacing = 0;
            col4.axis = .vertical;
            col4.isUserInteractionEnabled = true;
            col4.tag = index;
            col4.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.GoToDetails(gesture:))));
            


      
            // Put all the columns into the parent frames
            
            let renderer = UIStackView(arrangedSubviews: [col1,col2,col3,col4]);
            renderer.axis = .horizontal;
            renderer.distribution = .fillProportionally;
            renderer.alignment = .fill;
            renderer.translatesAutoresizingMaskIntoConstraints = true;
            renderer.spacing = 8;
            renderer.frame = CGRect(x: 10, y: CGFloat(index*60), width: view.frame.size.width-40, height: 60)
            // renderer.frame = CGRect(x: 0, y: CGFloat(index*60), width: view.frame.size.width, height: 60)
            // view.frame.size.width
            /*
            let lineView = UIView();
            
            lineView.addSubview(renderer);
            lineView.frame.size.height = 60;
            lineView.isUserInteractionEnabled = true;
            */
            IdentityList.addSubview(renderer);
            index = index + 1;
        }
        IdentityList.contentSize.height = CGFloat(index*60);
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
