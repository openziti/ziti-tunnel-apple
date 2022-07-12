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

import Cocoa
import NetworkExtension

class LogRotationConfigViewController: NSViewController {

    @IBOutlet weak var saveBtn: NSButton!
    @IBOutlet weak var countTextField: NSTextField!
    @IBOutlet weak var countStepper: NSStepper!
    @IBOutlet weak var dailyCheckbox: NSButton!
    @IBOutlet weak var sizeTextField: NSTextField!
    @IBOutlet weak var sizeStepper: NSStepper!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let defaults = ProviderConfig()
        self.countTextField.integerValue = defaults.logRotateCount
        self.countStepper.intValue = self.countTextField.intValue
        self.sizeTextField.integerValue = defaults.logRotateSizeMB
        self.countStepper.intValue = self.countTextField.intValue
        self.dailyCheckbox.state = defaults.logRotateDaily ? .on : .off
        
        guard
            let pp = TunnelMgr.shared.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = pp.providerConfiguration else {
            zLog.error("Unable to retrieve protocol connfiguration")
            return
        }
        
        if let countStr = conf[ProviderConfig.LOG_ROTATE_COUNT_KEY] as? String, let countInt = UInt32(countStr) {
            self.countTextField.intValue = Int32(countInt)
        }
        if let sizeStr = conf[ProviderConfig.LOG_ROTATE_SIZEMB_KEY] as? String, let sizeInt = UInt32(sizeStr) {
            self.sizeTextField.intValue = Int32(sizeInt)
        }
        if let daily = conf[ProviderConfig.LOG_ROTATE_DAILY_KEY] as? Bool {
            self.dailyCheckbox.state = daily ? .on : .off
        }
        
        countStepper.intValue = countTextField.intValue
        sizeStepper.intValue = sizeTextField.intValue
    }
    
    @IBAction func onCountStepper(_ sender: NSStepper) {
        countTextField.intValue = sender.intValue
    }
    
    @IBAction func onSizeStepper(_ sender: NSStepper) {
        sizeTextField.intValue = sender.intValue
    }
    
    @IBAction func onSave(_ sender: Any) {
        guard
            let pp = TunnelMgr.shared.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            var conf = pp.providerConfiguration else {
            zLog.error("Unable to access provider connfiguration")
            let alert = NSAlert()
            alert.messageText = "Access Error"
            alert.informativeText = "Unable to access provider configuration"
            alert.alertStyle = NSAlert.Style.critical
            alert.runModal()
            return
        }
        
        let daily = dailyCheckbox.state == .on ? true : false
        let count = countTextField.integerValue
        let sizeMB = sizeTextField.integerValue
        
        conf[ProviderConfig.LOG_ROTATE_COUNT_KEY] = countTextField.stringValue
        conf[ProviderConfig.LOG_ROTATE_SIZEMB_KEY] = sizeTextField.stringValue
        conf[ProviderConfig.LOG_ROTATE_DAILY_KEY] = daily
        
        pp.providerConfiguration = conf
        TunnelMgr.shared.tpm?.saveToPreferences { error in
            if let error = error {
                DispatchQueue.main.async {
                    zLog.error("Error saving updated provider configuration")
                    let alert = NSAlert()
                    alert.messageText = "Config Save Error"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = NSAlert.Style.critical
                    alert.runModal()
                }
                return
            }
            zLog.info("Saved provider configuration")
            
            Logger.updateRotateSettings(daily, count, sizeMB)
            
            // send a message to appex to update it's log rotation config...
            TunnelMgr.shared.ipcClient.sendToAppex(IpcUpdateLogRotateConfigMessage()) { _, zErr in
                guard zErr == nil else {
                    zLog.error("Unable to send provider message to reassert tunnel configuration: \(zErr!.localizedDescription)")
                    DispatchQueue.main.async {
                        zLog.error("Error sending message to appex to update log rotate config")
                        let alert = NSAlert()
                        alert.messageText = "Config IPC Error"
                        alert.informativeText = zErr!.localizedDescription
                        alert.alertStyle = NSAlert.Style.critical
                        alert.runModal()
                    }
                    return
                }
            }
        }
        
        NSApp.stopModal()
        self.view.window?.close()
    }
    
    @IBAction func onCancel(_ sender: Any) {
        NSApp.stopModal()
        self.view.window?.close()
    }
}
