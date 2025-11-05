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

class InAppNotification: NSView {
    var eventHandler:Any?
    
    static let edgeOffset = 10.0
    let logoSize = 48.0
    let borderWidth = 10.0
    let spacing = 3.0
    let totalWidth = 400.0
    
    var closeBtn:NSButton?
    var optionsBtn:NSButton?
    var optionsMenu: NSMenu!
    
    var topConstraint:NSLayoutConstraint?
    var trailingConstraint:NSLayoutConstraint?
        
    weak var parent:NotificationsPanel?
    var msg:IpcAppexNotificationMessage?
    
    init(_ parent:NotificationsPanel, _ msg:IpcAppexNotificationMessage) {
        super.init(frame: NSRect.zero)
        add(parent, msg)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func add(_ parent:NotificationsPanel, _ msg:IpcAppexNotificationMessage) {
        self.parent = parent
        self.msg = msg
        
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        self.layer?.cornerRadius = 17.5
        addShadow(self)
        
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
        if let logoImg = NSImage(named: "ziti-v2") {
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
        
        // Update intrinsic constraints to allow stack's .fillProportionally to calculate sizes
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
        topConstraint = NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.top,
                                           relatedBy: NSLayoutConstraint.Relation.equal, toItem: parent, attribute: NSLayoutConstraint.Attribute.top,
                                           multiplier: 1, constant: InAppNotification.edgeOffset)
        trailingConstraint = NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.trailing,
                                                relatedBy: NSLayoutConstraint.Relation.equal, toItem: parent, attribute: NSLayoutConstraint.Attribute.trailing,
                                                multiplier: 1, constant: totalWidth)
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.width,
                           relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute,
                           multiplier: 1, constant: totalWidth).isActive = true
        NSLayoutConstraint(item: self, attribute: NSLayoutConstraint.Attribute.height,
                           relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute,
                           multiplier: 1, constant: height).isActive = true
        
        topConstraint?.isActive = true
        trailingConstraint?.isActive = true
        
        layoutSubtreeIfNeeded()
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
    func remove() {
        if let ev = eventHandler {
            NSEvent.removeMonitor(ev)
        }
        parent?.remove(self)
    }
    
    @objc func onCloseButton() {
        self.remove()
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
         self.remove()
     }
    
    // Show/hit close button and options menu based on where the mouse is
    override func mouseEntered(with event: NSEvent) {
        closeBtn?.isHidden = false
        optionsBtn?.isHidden = msg?.actions?.count ?? 0 == 0
        parent?.notificationMouseEntered(self)
    }
    
    override func mouseExited(with event: NSEvent) {
        closeBtn?.isHidden = true
        optionsBtn?.isHidden = true
        parent?.notificationMouseExisted(self)
    }
    
    // triggered on any mouse up in the notice view except on close and options menu
    override func mouseUp(with event: NSEvent) {
        if let msg = msg {
            NotificationCenter.default.post(name: .onAppexNotification, object: self,
                                            userInfo: ["ipcMessage":IpcAppexNotificationActionMessage(msg.meta.zid, msg.category ?? "", "")])
        }
        self.remove()
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
}
