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

class RecoveryScreen: UIViewController, UIActivityItemSource {
    
    @IBOutlet var Column1: UIStackView!
    @IBOutlet var Column2: UIStackView!
    @IBOutlet var Column3: UIStackView!
    
    var identity:ZitiIdentity?;
    var idDetails:IdentityDetailScreen?;
    var zidMgr:ZidMgr?
    var tunnelMgr:TunnelMgr?
    var dashScreen:DashboardScreen?;
    
    override func viewDidLoad() {
        var codes = [String]()
        for i in 0..<20 {
            codes.append("Code-\(i)");
        }
        // Get the above codes from the identity.mfa.codes or somthing
        
        var index = 0;
        for i in 0..<codes.count {
            let code = codes[i];
            let codeLabel = UILabel();
            
            codeLabel.font = UIFont(name: "Open Sans", size: 22);
            codeLabel.textColor = UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0);
            codeLabel.frame = CGRect(x: 0, y: CGFloat(index*30), width: Column1.frame.size.width, height: 30);
            codeLabel.text = code;
            
            if ((i+1)>0) {
                if ((i+1)%3==0) {
                    Column3.addSubview(codeLabel);
                    index += 1;
                } else if ((i+1)%2==0) {
                    Column2.addSubview(codeLabel);
                } else {
                    Column1.addSubview(codeLabel);
                }
            } else {
                Column1.addSubview(codeLabel);
            }
        }
    }
    
    @IBAction func DoClose(_ sender: UITapGestureRecognizer) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func DoRegeneration(_ sender: UITapGestureRecognizer) {
        // Not sure what needs to be done here I think Clint calls a service and recalls the viewDidLoad setup
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
}
