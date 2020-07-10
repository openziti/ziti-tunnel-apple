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

class LogViewController: UIViewController, UIActivityItemSource {
    @IBOutlet weak var textView: UITextView!
    var refreshBtn:UIBarButtonItem?
    var shareBtn:UIBarButtonItem?
    var tag:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        refreshBtn = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(onRefresh))
        shareBtn = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.action, target: self, action: #selector(onShare))
        navigationItem.rightBarButtonItems = [shareBtn!, refreshBtn!]
        onRefresh()
    }
    
    @objc func onRefresh() {
        shareBtn?.isEnabled = false
        guard let url = logURL else { return }
        
        do {
            try textView.text = String(contentsOf: url, encoding: .utf8)
            if textView.text.count > 0 {
                refreshBtn?.isEnabled = true
                shareBtn?.isEnabled = true
            }
        } catch {
            textView.text = error.localizedDescription
            NSLog("No content found for log, \(error.localizedDescription)")
        }
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.scrollRangeToVisible(NSMakeRange(textView.text.count-1, 0))
    }
    
    @objc func onShare() {
        let items = [self]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(ac, animated: true)
    }
    
    var logURL:URL? {
        if let logger = Logger.shared, let tag = self.tag, let url = logger.currLog(forTag: tag) {
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
        
        return logURL?.lastPathComponent ?? "\(tag ?? "ziti").log"
    }
    
    
}
