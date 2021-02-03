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
import CZiti

class LogLevelScreen: NSViewController {
    
    var level = ZitiLog.LogLevel.ERROR;
    
    @IBOutlet var FatalImage: NSImageView!
    @IBOutlet var ErrorImage: NSImageView!
    @IBOutlet var WarnImage: NSImageView!
    @IBOutlet var InfoImage: NSImageView!
    @IBOutlet var DebugImage: NSImageView!
    @IBOutlet var VerboseImage: NSImageView!
    @IBOutlet var TraceImage: NSImageView!
    	
    @IBOutlet var ErrorButton: NSStackView!
    @IBOutlet var FatalButton: NSStackView!
    @IBOutlet var WarnButton: NSStackView!
    @IBOutlet var InfoButton: NSStackView!
    @IBOutlet var DebugButton: NSStackView!
    @IBOutlet var VerboseButton: NSStackView!
    @IBOutlet var TraceButton: NSStackView!
    @IBOutlet var GoBackButton: NSImageView!
    @IBOutlet var CloseButton: NSImageView!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    override func viewDidLoad() {
        level = ZitiLog.getLogLevel();
        SetIcon();
        SetupCursor();
    }
    
    func SetIcon() {
        TraceImage.isHidden = true;
        VerboseImage.isHidden = true;
        DebugImage.isHidden = true;
        InfoImage.isHidden = true;
        WarnImage.isHidden = true;
        ErrorImage.isHidden = true;
        FatalImage.isHidden = true;
        if (level==ZitiLog.LogLevel.TRACE) {
            TraceImage.isHidden = false;
        } else if (level==ZitiLog.LogLevel.VERBOSE) {
            VerboseImage.isHidden = false;
        } else if (level==ZitiLog.LogLevel.DEBUG) {
            DebugImage.isHidden = false;
        } else if (level==ZitiLog.LogLevel.INFO) {
            InfoImage.isHidden = false;
        } else if (level==ZitiLog.LogLevel.WARN) {
            WarnImage.isHidden = false;
        } else if (level==ZitiLog.LogLevel.ERROR) {
            ErrorImage.isHidden = false;
        } else if (level==ZitiLog.LogLevel.WTF) {
            FatalImage.isHidden = false;
        }
    }
    
    @IBAction func GoBack(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func SetFatal(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.WTF;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    @IBAction func SetError(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.ERROR;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    @IBAction func SetWarn(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.WARN;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    @IBAction func SetInfo(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.INFO;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    @IBAction func SetDebug(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.DEBUG;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    @IBAction func SetVerbose(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.VERBOSE;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    @IBAction func SetTrace(_ sender: NSClickGestureRecognizer) {
        level = ZitiLog.LogLevel.TRACE;
        TunnelMgr.shared.updateLogLevel(level);
        SetIcon();
    }
    
    func SetupCursor() {
        var items = [ErrorButton, FatalButton, WarnButton, InfoButton, DebugButton, VerboseButton, TraceButton];
        
        pointingHand = NSCursor.pointingHand;
        GoBackButton.addCursorRect(GoBackButton.bounds, cursor: pointingHand!);
        CloseButton.addCursorRect(CloseButton.bounds, cursor: pointingHand!);
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        GoBackButton.addTrackingRect(GoBackButton.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        CloseButton.addTrackingRect(CloseButton.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        }

        
        arrow = NSCursor.arrow
        GoBackButton.addCursorRect(GoBackButton.bounds, cursor: arrow!);
        CloseButton.addCursorRect(CloseButton.bounds, cursor: arrow!);
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        GoBackButton.addTrackingRect(GoBackButton.bounds, owner: arrow!, userData: nil, assumeInside: true);
        CloseButton.addTrackingRect(CloseButton.bounds, owner: arrow!, userData: nil, assumeInside: true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
        }
    }
}
