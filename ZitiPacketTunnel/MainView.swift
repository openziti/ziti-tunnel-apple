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

import Cocoa

class MainView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let superHit = super.hitTest(point)
        guard let vc = self.window?.contentViewController as? ViewController else { return superHit }
        
        if vc.notificationsPanel.notifications.count > 0 {
            for nv in vc.notificationsPanel.notifications {
                if superHit?.isDescendant(of: nv) ?? false {
                    return superHit
                }
            }
            if NSEvent.pressedMouseButtons != 0 {
                vc.notificationsPanel.removeAll()
            }
            return nil
        }
        return superHit
    }
}
