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

class NotificationsPanel: NSView {
    var constraintsSet = false
    var notifications:[InAppNotification] = []
    var dismissTimer:Timer?
    let dismissSecs = 5.0
    
    enum PendingAnimation {
        case Add(msg: IpcAppexNotificationMessage)
        case Remove(notification: InAppNotification)
        case RemoveAll
    }
    
    var animationInProgress = false
    var pendingAnimations:[PendingAnimation] = []
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    override func updateConstraints() {
        super.updateConstraints()
        guard !constraintsSet else { return }
        guard let superview = superview else { return }
        constraintsSet = true
        
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superview, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superview, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superview, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0).isActive = true
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 1, constant: 420).isActive = true
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func remove(_ notification:InAppNotification) {
        if self.animationInProgress {
            self.pendingAnimations.append(PendingAnimation.Remove(notification: notification))
        } else {
            self.animationInProgress = true
            self.notifications = self.notifications.filter { $0 != notification }
            notification.removeFromSuperview()
            self.repositionNotifications()
        }
    }
    
    func removeAll() {
        guard self.notifications.count > 0 else { return }
        
        if self.animationInProgress {
            self.pendingAnimations.append(PendingAnimation.RemoveAll)
        } else {
            self.animationInProgress = true
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.5
                    
                    self.notifications.forEach { curr in
                        var origin = curr.frame.origin
                        origin.x = (curr.frame.width + InAppNotification.edgeOffset)
                        curr.animator().frame.origin = origin
                    }
                }) {
                    while self.notifications.count > 0 {
                        let curr = self.notifications.removeFirst()
                        curr.removeFromSuperview()
                    }
                    self.animationInProgress = false
                    self.processPendingAnimations()
                }
            }
        }
    }
    
    func add(_ msg: IpcAppexNotificationMessage) {
        self.dismissTimer?.invalidate()
        self.dismissTimer = Timer.scheduledTimer(withTimeInterval: self.dismissSecs, repeats: false) { _ in
            self.removeAll()
        }
        
        if self.animationInProgress {
            self.pendingAnimations.append(PendingAnimation.Add(msg: msg))
        } else {
            self.animationInProgress = true
            let notification = InAppNotification(self, msg)
            self.notifications.insert(notification, at: 0)
            self.repositionNotifications()
        }
    }
    
    func repositionNotifications() {
        DispatchQueue.main.async {
            var y = self.frame.height
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5

                self.notifications.forEach { curr in
                    var origin = curr.frame.origin
                    if origin.x >= self.frame.width {
                        origin.x -= (curr.frame.width + InAppNotification.edgeOffset)
                    }
                    y = y - (curr.frame.height + InAppNotification.edgeOffset)
                    origin.y = y
                    curr.animator().frame.origin = origin
                }
            }) {
                var y = InAppNotification.edgeOffset
                self.notifications.forEach { curr in
                    curr.trailingConstraint?.isActive = false
                    curr.trailingConstraint = NSLayoutConstraint(item: curr, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: -InAppNotification.edgeOffset) // -(curr.edgeOffset))
                    curr.trailingConstraint?.isActive = true
                    
                    curr.topConstraint?.isActive = false
                    curr.topConstraint = NSLayoutConstraint(item: curr, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: y)
                    curr.topConstraint?.isActive = true
                    curr.layoutSubtreeIfNeeded()
                    y += (curr.frame.height + InAppNotification.edgeOffset)
                }
                self.animationInProgress = false
                self.processPendingAnimations()
            }
        }
    }
    
    func processPendingAnimations() {
        if let pA = self.pendingAnimations.first {
            switch pA {
            case .Add(let msgToAdd):
                self.pendingAnimations.removeFirst()
                self.add(msgToAdd)
            case .Remove(let notificationToRemove):
                self.pendingAnimations.removeFirst()
                self.remove(notificationToRemove)
            case .RemoveAll:
                self.pendingAnimations.removeFirst()
                self.removeAll()
            }
        }
    }
    
    func notificationMouseEntered(_ notification:InAppNotification) {
        self.dismissTimer?.invalidate()
        self.dismissTimer = nil
    }
    
    func notificationMouseExisted(_ notification:InAppNotification) {
        if self.dismissTimer == nil {
            self.dismissTimer = Timer.scheduledTimer(withTimeInterval: self.dismissSecs, repeats: false) { _ in
                self.removeAll()
            }
        }
    }
}
