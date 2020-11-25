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


class LogDetailScreen: UIViewController, UIActivityItemSource {
    
    var logType: String?
    @IBOutlet weak var LogTitle: UILabel!
    @IBOutlet weak var LogText: UITextView!
    @IBOutlet weak var ShareButton: UIImageView!
    
    @IBAction func dismissVC(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    
    override func viewDidLoad() {
        let logger = Logger.shared;
        guard let url = logger!.currLog(forTag: Logger.APP_TAG) else { return };
        LogTitle.text = "  Application Logs";
        if (logType=="packet") {
            LogTitle.text = "  Packet Tunnel Logs";
            guard let url = logger!.currLog(forTag: Logger.TUN_TAG) else { return };
        }
        
        do {
            try LogText.text = String(contentsOf: url, encoding: .utf8);
            ShareButton?.isHidden = (LogText.text.count>0);
        } catch {
            LogText.text = error.localizedDescription
            NSLog("No content found for log, \(error.localizedDescription)")
        }
        
        LogText.layoutManager.allowsNonContiguousLayout = false;
        LogText.scrollRangeToVisible(NSMakeRange(LogText.text.count-1, 0));
    }
    
    
}
