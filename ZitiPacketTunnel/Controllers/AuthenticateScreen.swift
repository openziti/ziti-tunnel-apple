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

import Cocoa

class AuthenticateScreen: NSViewController {
    
    @IBOutlet var AuthCode: NSTextField!
    @IBOutlet var AuthTypeTitle: NSTextField!
    
    var isRecovery = false;
    
    override func viewDidLoad() {
        isRecovery = false;
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func SwitchClicked(_ sender: NSClickGestureRecognizer) {
        isRecovery = !isRecovery;
    }
    
    func setType() {
        if (isRecovery) {
            AuthTypeTitle.stringValue = "Recovery Code";
        } else {
            AuthTypeTitle.stringValue = "Authentication Code";
        }
    }
    
    @IBAction func AuthClicked(_ sender: NSClickGestureRecognizer) {
        var code = AuthCode.stringValue;
        // Do authentication
    }
    
}
