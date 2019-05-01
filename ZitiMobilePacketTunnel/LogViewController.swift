//
//  LogViewController.swift
//  ZitiMobilePacketTunnel
//
//  Created by David Hart on 4/30/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import UIKit

class LogViewController: UIViewController, UIActivityItemSource {
    @IBOutlet weak var textView: UITextView!
    var shareBtn:UIBarButtonItem?
    var tag:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        shareBtn = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.action, target: self, action: #selector(onShare))
        navigationItem.rightBarButtonItem = shareBtn
        shareBtn?.isEnabled = false

        if let url = logURL {
            do {
                try textView.text = String(contentsOf: url, encoding: .utf8)
                if textView.text.count > 0 {
                    shareBtn?.isEnabled = true
                }
            } catch {
                textView.text = error.localizedDescription
                NSLog("No content found for log, \(error.localizedDescription)")
            }
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
