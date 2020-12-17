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
import CZiti

class LogLevelScreen: UIViewController, UIActivityItemSource {
    
    @IBOutlet weak var FatalImage: UIImageView!
    @IBOutlet weak var ErrorImage: UIImageView!
    @IBOutlet weak var WarnImage: UIImageView!
    @IBOutlet weak var InfoImage: UIImageView!
    @IBOutlet weak var DebugImage: UIImageView!
    @IBOutlet weak var VerboseImage: UIImageView!
    @IBOutlet weak var TraceImage: UIImageView!
    
    override func viewDidAppear(_ animated: Bool) {
        Reset();
        let level = ZitiLog.getLogLevel();
        if (level==ZitiLog.LogLevel.WTF) {
            FatalImage.alpha = 1.0;
        } else if (level==ZitiLog.LogLevel.ERROR) {
            ErrorImage.alpha = 1.0;
        } else if (level==ZitiLog.LogLevel.WARN) {
            WarnImage.alpha = 1.0;
        } else if (level==ZitiLog.LogLevel.INFO) {
            InfoImage.alpha = 1.0;
        } else if (level==ZitiLog.LogLevel.DEBUG) {
            DebugImage.alpha = 1.0;
        } else if (level==ZitiLog.LogLevel.VERBOSE) {
            VerboseImage.alpha = 1.0;
        } else if (level==ZitiLog.LogLevel.TRACE) {
            TraceImage.alpha = 1.0;
        }
    }
    
    func Reset() {
        FatalImage.alpha = 0;
        ErrorImage.alpha = 0;
        WarnImage.alpha = 0;
        InfoImage.alpha = 0;
        DebugImage.alpha = 0;
        VerboseImage.alpha = 0;
        TraceImage.alpha = 0;
    }
    
    @IBAction func dismissVC(_ sender: Any) {
         dismiss(animated: true, completion: nil)
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @IBAction func SetFatal(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.WTF);
        dismiss(animated: true, completion: nil);
    }
    
    @IBAction func SetError(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.ERROR);
        dismiss(animated: true, completion: nil);
    }
    
    @IBAction func SetWarn(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.WARN);
        dismiss(animated: true, completion: nil);
    }
    
    @IBAction func SetInfo(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.INFO);
        dismiss(animated: true, completion: nil);
    }
    
    @IBAction func SetDebug(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.DEBUG);
        dismiss(animated: true, completion: nil);
    }
    
    @IBAction func SetVerbose(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.VERBOSE);
        dismiss(animated: true, completion: nil);
    }
    
    @IBAction func SetTrace(_ sender: UITapGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.TRACE);
        dismiss(animated: true, completion: nil);
    }
}

