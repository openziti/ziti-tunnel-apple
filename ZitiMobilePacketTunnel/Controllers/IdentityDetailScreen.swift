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
    
    @IBOutlet weak var IdName: UITextField!
    @IBOutlet weak var IdNetwork: UITextField!
    @IBOutlet weak var IdStatus: UITextField!
    @IBOutlet weak var IdEnrollment: UITextField!
    @IBOutlet weak var IdVersion: UITextField!
    @IBOutlet weak var IdServiceCount: UILabel!
    
    var zid:ZitiIdentity?
    
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
        
    }
    
    override func viewDidLoad() {
        IdName.text = zid?.name;
        IdNetwork.text = zid?.czid?.ztAPI;
        IdVersion.text = zid?.controllerVersion ?? "unknown";
        IdEnrollment.text = zid?.enrollmentStatus.rawValue;
        IdServiceCount.text = zid?.services.count ?? 0+" Services";
        
        let cs = zid?.edgeStatus ?? ZitiIdentity.EdgeStatus(0, status:.None)
        var csStr = ""
        if zid?.isEnrolled ?? false == false {
            csStr = "None"
        } else if cs.status == .PartiallyAvailable {
            csStr = "Partially Available"
        } else {
            csStr = cs.status.rawValue
        }
        csStr += " (as of \(DateFormatter().timeSince(cs.lastContactAt)))"
        IdStatus.text = csStr;
    }
    
}
