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
import CZiti
import SwiftUI

@IBDesignable
class IdentityListitem: UIView {
    
    @IBOutlet var ServiceCount: UIView!
    @IBOutlet var TimeoutImage: UIImageView!
    @IBOutlet var MfaImage: UIImageView!
    @IBOutlet var LockoutImage: UIImageView!
    @IBOutlet var ServiceLabel: UILabel!
    @IBOutlet var IdentityLabel: UILabel!
    @IBOutlet var ServerUrl: UILabel!
    @IBOutlet var ServicesLabel: UILabel!
    @IBOutlet var ToggleImage: UIImageView!
    @IBOutlet var ToggledOnImage: UIImageView!
    @IBOutlet var ToggleLabel: UILabel!
    var zid:ZitiIdentity!;
    var tunnelMgr = TunnelMgr.shared;
    var timer = Timer();
    var vc:DashboardScreen!;
    let XIB = "IdentityListItem";
    var isMfaRequired = false;
    var wasNotified = false;
    var needsMfa = 0;
    var hasMfa = 0;
    var totalServices = 0;
    var maxTimeout = Int32(-1);
    var minTimeout = Int32(-1);
    
    public func setIdentity(identity:ZitiIdentity, vc:DashboardScreen) {
        self.vc = vc;
        zid = identity;
        ToggledOnImage.isHidden = true;
        ToggleImage.isHidden = true;
        if (zid.isEnabled) {
            ToggleLabel?.text = "enabled";
            ToggledOnImage.isHidden = false;
        } else {
            ToggleLabel?.text = "disabled";
            ToggleImage.isHidden = false;
        }
        IdentityLabel?.text = zid.name;
        ServerUrl?.text = zid.czid?.ztAPI ?? "no network";
        ServiceLabel?.text = String(zid.services.count);
        //self.CheckMfaRequiredByChecks();
        if (zid.isMfaEnabled) {
            if (!zid.isMfaVerified) {
                // Needs Authentication opposed to service authorization
                ShowImage(name: "mfa");
            }
        }
    }
    
    public func ShowImage(name: String) {
        ServiceCount.isHidden = true;
        MfaImage.isHidden = true;
        LockoutImage.isHidden = true;
        TimeoutImage.isHidden = true;
        
        if (name == "timeout") {
            TimeoutImage.isHidden = false;
        } else if (name == "authorize") {
            LockoutImage.isHidden = false;
            ServicesLabel.text = "authorize";
        } else if (name == "mfa") {
            MfaImage.isHidden = false;
            ServicesLabel.text = "authenticate";
        } else {
            ServiceCount.isHidden = false;
            ServicesLabel.text = "services";
        }
    }
    
    @IBAction func ToggleOnGesture(_ sender: Any) {
        
    }
    
    @IBAction func ToggleOffGesture(_ sender: UITapGestureRecognizer) {
    }
    
}
