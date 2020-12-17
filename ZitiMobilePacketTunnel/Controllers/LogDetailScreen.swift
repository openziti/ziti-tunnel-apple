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
    
    @objc func onRefresh() {
        ShareButton?.isHidden = true
        guard let url = logURL else { return }
        
        do {
            try LogText.text = String(contentsOf: url, encoding: .utf8)
            if LogText.text.count > 0 {
                ShareButton?.isHidden = false
            }
        } catch {
            LogText.text = error.localizedDescription
            zLog.error("No content found for log, \(error.localizedDescription)")
        }
        LogText.layoutManager.allowsNonContiguousLayout = false
        LogText.scrollRangeToVisible(NSMakeRange(LogText.text.count-1, 0))
    }
    
    @objc func onShare() {
        let items = [self]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(ac, animated: true)
    }
    
    var logURL:URL? {
        if let logger = Logger.shared, let tag = self.logType, let url = logger.currLog(forTag: tag) {
            return url
        }
        return nil
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        if let url = logURL {
            return url
        }
        return "Log not available"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        
        return activityViewControllerPlaceholderItem(activityViewController)
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        
        return logURL?.lastPathComponent ?? "\(logType ?? "ziti").log"
    }
    
    override func viewDidLoad() {
        LogTitle.text = "  Application Logs";
        if (logType=="packet") {
            LogTitle.text = "  Packet Tunnel Logs";
        }
        self.onRefresh();
    }
    
    
}
