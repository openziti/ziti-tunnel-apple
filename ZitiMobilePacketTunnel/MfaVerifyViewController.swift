//
// Copyright NetFoundry Inc.
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

class MfaVerifyViewController: UIViewController {
    
    @IBOutlet weak var imgView: UIImageView!
    @IBOutlet weak var urlTextView: UITextView!
    @IBOutlet weak var textField: UITextField!
    
    var provisioningUrl:String?
    var code:String?
    
    var completionHandler:((String?)->Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let provisioningUrl = provisioningUrl else {
            zLog.error("Invalid (nil) provisioningUrl")
            return
        }

        guard let img = generateQRCode(provisioningUrl) else {
            zLog.error("Unable to generate QR code")
            return
        }
        imgView.image = img
        
        if let url = URL(string: provisioningUrl) {
            var secret:String = provisioningUrl
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true), let queryItems = components.queryItems {
                for i in queryItems {
                    if i.name == "secret" {
                        secret = i.value ?? provisioningUrl
                        break
                    }
                }
            }
            let attributedString = NSMutableAttributedString(string: secret)
            let font = UIFont.systemFont(ofSize: 20.0)
            attributedString.setAttributes([.link: url, .font: font], range: NSMakeRange(0, secret.count))
            urlTextView.attributedText = attributedString
        } else {
            urlTextView.text = provisioningUrl
        }
        urlTextView.textAlignment = .center
        urlTextView.textColor = .blue
        
        textField.placeholder = "Authentication Code"
        
        // dimiss keyboard if tap outside of any control...
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        self.isModalInPresentation = true
    }
    
    func generateQRCode(_ string: String) -> UIImage? {
        let data = string.data(using: .utf8)

        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 3, y: 3)
            if let output = filter.outputImage?.transformed(by: transform) {
                return UIImage(ciImage: output)
            }
        }
        return nil
    }
    
    @IBAction func onOk(_ sender: Any) {
        completionHandler?(textField.text)
    }
    
    @IBAction func onCancel(_ sender: Any) {
        code = nil
        completionHandler?(nil)
    }
}
