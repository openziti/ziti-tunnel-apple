//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
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
