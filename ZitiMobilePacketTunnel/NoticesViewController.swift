//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import UIKit

class NoticesViewController: UIViewController {
    @IBOutlet weak var textView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let rtfPath = Bundle.main.url(forResource:"Notices", withExtension: "rtf") {
            do {
                let attributedStringWithRtf = try NSAttributedString(url: rtfPath, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                textView.attributedText = attributedStringWithRtf
            } catch {
                NSLog("NoticesViewConroller: No content found!")
            }
        }
    }
}
