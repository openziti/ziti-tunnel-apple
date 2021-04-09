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

class AuthenticateScreen: UIViewController, UIActivityItemSource, UITextFieldDelegate {
    
    @IBOutlet var AuthCode: UITextField!
    
    var identity:ZitiIdentity?;
    var idDetails:IdentityDetailScreen?;
    var zidMgr:ZidMgr?
    var tunnelMgr:TunnelMgr?
    var dashScreen:DashboardScreen?;
    
    override func viewDidLoad() {
        AuthCode.smartInsertDeleteType = UITextSmartInsertDeleteType.no
        AuthCode.delegate = self
        AuthCode.text = "";
    }
    
    @IBAction func DoClose(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func DoAuth(_ sender: Any) {
        var code = AuthCode.text;
        // Do the authenticate and somehow tell the id details page to update UIs, I will figure out when Dave sends me the event
        dismiss(animated: true, completion: nil)
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let textFieldText = textField.text,
            let rangeOfTextToReplace = Range(range, in: textFieldText) else {
                return false
        }
        let substringToReplace = textFieldText[rangeOfTextToReplace]
        let count = textFieldText.count - substringToReplace.count + string.count
        return count <= 8
    }
}

