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

import Foundation
import Cocoa

func performKeyEquivalent(with event: NSEvent, from target:Any) -> Bool {
    let commandKey = NSEvent.ModifierFlags.command.rawValue
    let commandShiftKey = NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue
    
    if event.type == NSEvent.EventType.keyDown {
        if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue) == commandKey {
            switch event.charactersIgnoringModifiers! {
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: target) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: target) { return true }
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: target) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: target) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: target) { return true }
            default:
                break
            }
        } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue) == commandShiftKey {
            if event.charactersIgnoringModifiers == "Z" {
                if NSApp.sendAction(Selector(("redo:")), to: nil, from: target) { return true }
            }
        }
    }
    return false
}

class EditableNSTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Ziti_Desktop_Edge.performKeyEquivalent(with: event, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

class EditableNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Ziti_Desktop_Edge.performKeyEquivalent(with: event, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
