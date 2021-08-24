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

import Cocoa

class SnapshotViewController: NSViewController, NSSharingServicePickerDelegate {

    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet var textView: NSTextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    @IBAction func handleShareButton(_ sender: NSToolbarItem) {
        let text = textView.textStorage?.mutableString ?? "no connectivity status data available"
        let sharingPicker = NSSharingServicePicker(items: [text])
        let bounds = NSRect(x: view.bounds.width - 30, y: view.bounds.minY + 15, width: 30, height: view.bounds.height)
        
        sharingPicker.delegate = self
        sharingPicker.show(relativeTo: bounds, of: self.view, preferredEdge: .minY)
    }
}
