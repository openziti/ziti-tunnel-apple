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

class RecoveryScreen: NSViewController {
    
    var codes = [String]();
    
    @IBOutlet var Code1: NSTextField!
    @IBOutlet var Code2: NSTextField!
    @IBOutlet var Code3: NSTextField!
    @IBOutlet var Code4: NSTextField!
    @IBOutlet var Code5: NSTextField!
    @IBOutlet var Code6: NSTextField!
    @IBOutlet var Code7: NSTextField!
    @IBOutlet var Code8: NSTextField!
    @IBOutlet var Code9: NSTextField!
    @IBOutlet var Code10: NSTextField!
    @IBOutlet var Code11: NSTextField!
    @IBOutlet var Code12: NSTextField!
    @IBOutlet var Code13: NSTextField!
    @IBOutlet var Code14: NSTextField!
    @IBOutlet var Code15: NSTextField!
    @IBOutlet var Code16: NSTextField!
    @IBOutlet var Code17: NSTextField!
    @IBOutlet var Code18: NSTextField!
    @IBOutlet var Code19: NSTextField!
    @IBOutlet var Code20: NSTextField!
    
    override func viewDidLoad() {
        Code1.stringValue = codes.count>0 ? codes[0] : "";
        Code2.stringValue = codes.count>1 ? codes[1] : "";
        Code3.stringValue = codes.count>2 ? codes[2] : "";
        Code4.stringValue = codes.count>3 ? codes[3] : "";
        Code5.stringValue = codes.count>4 ? codes[4] : "";
        Code6.stringValue = codes.count>5 ? codes[5] : "";
        Code7.stringValue = codes.count>6 ? codes[6] : "";
        Code8.stringValue = codes.count>7 ? codes[7] : "";
        Code9.stringValue = codes.count>8 ? codes[8] : "";
        Code10.stringValue = codes.count>9 ? codes[9] : "";
        Code11.stringValue = codes.count>10 ? codes[10] : "";
        Code12.stringValue = codes.count>11 ? codes[11] : "";
        Code13.stringValue = codes.count>12 ? codes[12] : "";
        Code14.stringValue = codes.count>13 ? codes[13] : "";
        Code15.stringValue = codes.count>14 ? codes[14] : "";
        Code16.stringValue = codes.count>15 ? codes[15] : "";
        Code17.stringValue = codes.count>16 ? codes[16] : "";
        Code18.stringValue = codes.count>17 ? codes[17] : "";
        Code19.stringValue = codes.count>18 ? codes[18] : "";
        Code20.stringValue = codes.count>19 ? codes[19] : "";
    }
    
    @IBAction func RegenClicked(_ sender: NSClickGestureRecognizer) {
        // Call recovery code regen service
    }
    
    @IBAction func SaveClicked(_ sender: NSClickGestureRecognizer) {
        // Prompt to save to file
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
}
