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

class ResizableTestView : NSTextView {
//    override var intrinsicContentSize: CGSize {
//        return CGSize(width: frame.width, height: frame.height)
//    }
    
    func initAndSize(_ str:String, _ width:CGFloat, _ bold:Bool) {
        self.font = bold ? NSFont.boldSystemFont(ofSize: 14) : NSFont.systemFont(ofSize: 14)
        self.string = str
        self.alignment = .left
        self.isEditable = false
        self.drawsBackground = false
        self.textColor = .textColor
        self.isVerticallyResizable = true
        self.isHorizontallyResizable = true
        self.textContainer?.widthTracksTextView = false
        self.textContainer?.heightTracksTextView = false
        self.textContainer?.size.width = width
        self.maxSize = NSSize(width: width, height: 500)
        self.sizeToFit()
    }
}

class OptionsButton: NSButton {
    override open func draw(_ dirtyRect: NSRect) {
        self.highlight(true)
        super.draw(dirtyRect)
    }
}

class InAppdNotification: NSView {
    var eventHandler:Any?
    var dismissTimer:Timer?
    let dismissSecs = 5.0
    let logoSize = 48.0
    let borderWidth = 10.0
    let spacing = 3.0
    let totalWidth = 400.0
    
    var closeBtn:NSButton?
    var optionsBtn:NSButton?
    var optionsMenu: NSMenu!
    
    static var allNotices:[InAppdNotification] = []
    
    weak var parent:NSView?
    var msg:IpcAppexNotificationMessage?

    func show(_ parent:NSView, _ msg:IpcAppexNotificationMessage) {
        self.parent = parent
        self.msg = msg
        
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.layer?.cornerRadius = 17.5
        addShadow(self)
        
        let edgeOffset = 10.0 + (Double(InAppdNotification.allNotices.count) * 10.0)
        let textWidth = totalWidth - (borderWidth*2) - logoSize
        
        // Close Button
        if let closeImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") {
            closeBtn = NSButton(image: closeImg, target: self, action: #selector(onCloseButton))
            closeBtn?.frame = NSMakeRect(0, 0, 24, 24)
            closeBtn?.bezelStyle = .circular
            closeBtn?.isBordered = false
            closeBtn?.imageScaling = .scaleProportionallyUpOrDown
            closeBtn?.contentTintColor = .windowBackgroundColor
            closeBtn?.wantsLayer = true
            if let cbtn = closeBtn {
                addShadow(cbtn)
                self.addSubview(cbtn)
                cbtn.isHidden = true
            }
        }
        
        // Logo image
        var logoView:NSView?
        if let logoImg = NSImage(named: "ZitiLogo64") {
            logoView = NSImageView(image: logoImg)
            logoView?.frame = NSRect(x: 0, y: 0, width: logoSize, height: logoSize)
            if let lv = logoView { self.addSubview(lv) }
        }
                        
        // Heading text
        let headingTextView = ResizableTestView()
        let headingText = msg.subtitle ?? msg.title ?? ""
        headingTextView.initAndSize(headingText, textWidth, true)
        self.addSubview(headingTextView)
        
        // Body Test
        let bodyTextView = ResizableTestView()
        let bodyText = msg.body ?? ""
        bodyTextView.initAndSize(bodyText, textWidth, false)
        self.addSubview(bodyTextView)
        
        // Add self to parent view
        parent.addSubview(self)
        
        // Update intrinsic constraints to all stack's .fillProportionally to calculate sizes
        //headingTextView.invalidateIntrinsicContentSize()
        //bodyTextView.invalidateIntrinsicContentSize()
        
        // Position everything
        let height = headingTextView.frame.height + bodyTextView.frame.height + (borderWidth*2) + spacing
        closeBtn?.frame.origin.x = -((closeBtn?.frame.height ?? 0) * 0.25)
        closeBtn?.frame.origin.y = height - ((closeBtn?.frame.height ?? 0) * 0.75)
        logoView?.frame.origin.x = borderWidth / 1.5
        logoView?.frame.origin.y = height/2.0 - (logoSize / 2.0)
        headingTextView.frame.origin.x = borderWidth + logoSize
        headingTextView.frame.origin.y = (height-(borderWidth + headingTextView.frame.height))
        bodyTextView.frame.origin.x = borderWidth + logoSize
        bodyTextView.frame.origin.y =  borderWidth 
        
        if let img = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "open") {
            optionsBtn = OptionsButton(title: "Options", image: img, target: self, action: #selector(onOptionsButton))
            optionsBtn?.imagePosition = .imageTrailing
        } else {
            optionsBtn = OptionsButton(title: "Options", target: self, action: #selector(onOptionsButton))
        }
        
        if let obtn = optionsBtn {
            obtn.font = NSFont.systemFont(ofSize: 12)
            obtn.frame.origin.x = totalWidth - (optionsBtn?.frame.width ?? 0.0)
            obtn.frame.origin.y = 0
            self.addSubview(obtn)
            obtn.isHidden = true
        }
        
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: parent, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: edgeOffset).isActive = true
        let trailing = NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: parent, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: (totalWidth + edgeOffset))
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 1, constant: totalWidth).isActive = true
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 1, constant: height).isActive = true
        trailing.isActive = true
        
        // Slide the notication in...
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                var origin = self.frame.origin
                origin.x -= self.frame.width + edgeOffset
                self.animator().frame.origin = origin
            }) {
                // Handle completion
                trailing.isActive = false
                NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: parent, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: -(edgeOffset)).isActive = true
            }
        }
        
        // Slide notification out if nothing happens for a few secs
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissSecs, repeats: false) { _ in
            self.dismiss(true)
        }
        
        // Dismiss on mouse click outside of the notification window
        eventHandler = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            if let pt = self?.window?.mouseLocationOutsideOfEventStream, let theView = self?.window?.contentView?.hitTest(pt) {
                if (theView as? InAppdNotification == nil) && theView.superview != self {
                    self?.isHidden = true
                }
            } else {
                self?.isHidden = true
            }
            return event
        }
        InAppdNotification.allNotices.append(self)
    }
    
    // make hits on any subview (except the close and options buttons) show up here (so we can react to any click...)
    override func hitTest(_ point: NSPoint) -> NSView? {
        let superHit = super.hitTest(point)
        if superHit != nil && superHit != closeBtn && superHit != optionsBtn {
            return self
        }
        return superHit
    }
    
    func addShadow(_ v:NSView) {
        v.shadow = NSShadow()
        v.layer?.shadowColor = NSColor.black.cgColor
        v.layer?.shadowOpacity = 0.1
        v.layer?.shadowOffset = CGSize(width: 0, height: 0)
        v.layer?.shadowRadius = 3
        v.layer?.masksToBounds = false
    }
     
    // drop all references so can be free'd up
    func destroy() {
        self.dismissTimer?.invalidate()
        self.dismissTimer = nil
        
        if let ev = eventHandler {
            NSEvent.removeMonitor(ev)
        }
        self.removeFromSuperview()
        InAppdNotification.allNotices = InAppdNotification.allNotices.filter { $0 != self }
    }
    
    func dismiss(_ animate:Bool) {
        if animate {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                var origin = self.frame.origin
                origin.x += self.frame.width
                self.animator().frame.origin = origin
            }) {
                self.destroy()
            }
        } else {
            self.destroy()
        }
    }
    
    @objc func onCloseButton() {
        self.destroy()
    }
    
    // Options Menu
    func newMenuItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: #selector(handleMenuItemSelected), keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }
    
    @objc func onOptionsButton(_ sender: NSButton) {
        self.optionsMenu = NSMenu()

        self.msg?.actions?.forEach{ actionStr in
            if let action = UserNotifications.Action(rawValue: actionStr) {
                self.optionsMenu.addItem(newMenuItem(action.title))
            }
        }
        let location = NSPoint(x: 0, y: sender.frame.height - 5)
        self.optionsMenu.popUp(positioning: nil, at: location, in: sender)
    }
                                         
     @objc func handleMenuItemSelected(_ sender: AnyObject) {
         guard let menuItem = sender as? NSMenuItem else { return }
         let actionStr = UserNotifications.Action.actionForTitle(menuItem.title)?.rawValue ?? ""
         if let msg = msg {
             NotificationCenter.default.post(name: .onAppexNotification, object: self,
                                             userInfo: ["ipcMessage":IpcAppexNotificationActionMessage(msg.meta.zid, msg.category ?? "", actionStr)])
         }
         self.destroy()
     }
    
    // Show/hit close button and options menu based on where the mouse is
    override func mouseEntered(with event: NSEvent) {
        self.dismissTimer?.invalidate()
        self.dismissTimer = nil
        closeBtn?.isHidden = false
        optionsBtn?.isHidden = false
    }
    
    override func mouseExited(with event: NSEvent) {
        if dismissTimer == nil {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: self.dismissSecs, repeats: false) { _ in
                self.dismiss(true)
            }
        }
        closeBtn?.isHidden = true
        optionsBtn?.isHidden = true
    }
    
    // to pick-up the mouse events from all views inside this notice view
    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        let options:NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    // triggered on any mouse up in the notice view except on close and options menu
    override func mouseUp(with event: NSEvent) {
        // if not in front, bring to front.  Otherwise do the default action.
        if InAppdNotification.allNotices.count > 1 {
            let constraints = self.constraints
            self.removeFromSuperview()
            constraints.forEach { self.addConstraint($0) }
            self.parent?.addSubview(self)
        } else {
            if let msg = msg {
                NotificationCenter.default.post(name: .onAppexNotification, object: self,
                                                userInfo: ["ipcMessage":IpcAppexNotificationActionMessage(msg.meta.zid, msg.category ?? "", "")])
            }
            self.destroy()
        }
    }
}
