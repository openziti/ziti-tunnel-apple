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
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
       // Rebuild the list
    }
    
    func onRemovedId(_ idString: String) {
        // Rebuild the list
    }
    
    
    var isMenuOpen = false
    var originalDashTransform:CGAffineTransform!
    var originalBgTransform:CGAffineTransform!
    var tunnelMgr = TunnelMgr.shared
    
    @IBOutlet weak var ConnectButton: UIImageView!
    @IBOutlet weak var ConnectedButton: UIView!
    @IBOutlet weak var Dashboard: UIStackView!
    @IBOutlet weak var Background: UIView!
    
    
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
    
    
    // Copied From Daves Controller
    
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
