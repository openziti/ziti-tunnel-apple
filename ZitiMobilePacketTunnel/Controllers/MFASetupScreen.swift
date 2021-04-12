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

import Foundation
import UIKit
import CZiti
import CoreImage.CIFilterBuiltins

@available(iOS 13.0, *)
class MFASetupScreen: UIViewController, UIActivityItemSource, UITextFieldDelegate {
    
    @IBOutlet var IdentityName: UILabel!
    @IBOutlet var BarCode: UIImageView!
    @IBOutlet var SecretCode: UILabel!
    @IBOutlet var AuthCode: UITextField!
    @IBOutlet var AuthButton: UIButton!
    @IBOutlet var ToggleSecretButton: UILabel!
    @IBOutlet var GoToLinkButton: UILabel!
    @IBOutlet var CloseButton: UIStackView!
    
    let context = CIContext();
    let filter = CIFilter.qrCodeGenerator();
    
    var url:String = "";
    var secret:String = "";
    var identity:ZitiIdentity?;
    var idDetails:IdentityDetailScreen?;
    var zidMgr:ZidMgr?
    var tunnelMgr:TunnelMgr?
    var dashScreen:DashboardScreen?;
    
    override func viewDidLoad() {
        AuthCode.smartInsertDeleteType = UITextSmartInsertDeleteType.no
        AuthCode.delegate = self
        AuthCode.text = "";
        IdentityName.text = identity?.name;
        url = "https://netfoundry.io"; // get url from MFA object
        secret = "546545645";
        ToggleSecretButton.text = "Secret \(secret)"; // get from MFA object
        
        
        let data = Data(url.utf8);
        filter.setValue(data, forKey: "inputMessage");
        let transform = CGAffineTransform(scaleX: 3, y: 3)
        if let qrCodeImage = filter.outputImage?.transformed(by: transform) {
            if let qrCodeCGImage = context.createCGImage(qrCodeImage, from: qrCodeImage.extent) {
                BarCode.image = UIImage(cgImage: qrCodeCGImage, scale: 3.0, orientation: .down);
            }
        }
    }
    
    func generateQRCode(from string: String) -> UIImage {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")

        if let outputImage = filter.outputImage {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }

        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    
    @IBAction func CopySecret(_ sender: UITapGestureRecognizer) {
        let pasteboard = UIPasteboard.general;
        pasteboard.string = secret;
        showToast(message: "\(secret) copied to clipboard")
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let textFieldText = textField.text,
            let rangeOfTextToReplace = Range(range, in: textFieldText) else {
                return false
        }
        let substringToReplace = textFieldText[rangeOfTextToReplace]
        let count = textFieldText.count - substringToReplace.count + string.count
        return count <= 6
    }
    
    func showToast(message : String) {

        let toastLabel = UILabel(frame: CGRect(x: self.view.frame.size.width/2 - 160, y: self.view.frame.size.height-100, width: 320, height: 35))
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center;
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10;
        toastLabel.clipsToBounds  =  true
        self.view.addSubview(toastLabel)
        UIView.animate(withDuration: 4.0, delay: 0.1, options: .curveEaseOut, animations: {
             toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        });
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    @IBAction func DoUrlAuth(_ sender: UITapGestureRecognizer) {
        let mfaurl = URL (string: url)!
        UIApplication.shared.open (mfaurl)
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @IBAction func DoClose(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func DoAuthorization(_ sender: UITapGestureRecognizer) {
        // Call the authorization service
        dismiss(animated: true, completion: nil)
    }
}

