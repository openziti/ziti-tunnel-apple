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
import NetworkExtension
import CZiti

class DashboardScreen: NSViewController, NSWindowDelegate, ZitiIdentityStoreDelegate {
    
    @IBOutlet var AddButton: NSStackView!
    @IBOutlet var AddIdButton: NSTextField!
    @IBOutlet var ConnectButton: NSImageView!
    @IBOutlet var ConnectedButton: NSBox!
    @IBOutlet weak var MenuButton: NSStackView!
    @IBOutlet weak var ParentView: NSView!
    @IBOutlet var Background: NSImageView!
    @IBOutlet var IdentityList: NSScrollView!
    @IBOutlet var TimerLabel: NSTextField!
    @IBOutlet var UpSpeed: NSTextField!
    @IBOutlet var UpSpeedSize: NSTextField!
    @IBOutlet var DownSpeed: NSTextField!
    @IBOutlet var DownSpeedSize: NSTextField!
    @IBOutlet var SpeedArea: NSStackView!
    var timer = Timer();
    var timeLaunched:Int = 0;
    
    let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Ziti"
    var tunnelMgr = TunnelMgr.shared;
    var zidMgr = ZidMgr();
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    private var bytesDown:Float = 0.0;
    private var bytesUp:Float = 0.0;
    
    override func viewWillAppear() {
        self.view.window?.titleVisibility = .hidden;
        self.view.window?.titlebarAppearsTransparent = true;

        self.view.window?.styleMask.insert(.fullSizeContentView);

        self.view.window?.styleMask.remove(.closable);
        self.view.window?.styleMask.remove(.fullScreen);
        self.view.window?.styleMask.remove(.miniaturizable);
        self.view.window?.styleMask.remove(.resizable);
        
        Background.layer?.cornerRadius = 30;
        Background.layer?.masksToBounds = true;
        self.view.window?.isOpaque = false;
        self.view.window?.hasShadow = false;
        self.view.window?.backgroundColor = NSColor.clear;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        Logger.initShared(Logger.APP_TAG);
        zLog.info(Version.verboseStr);
        
        zidMgr.zidStore.delegate = self;
        
        self.view.window?.setFrame(NSRect(x:0,y:0,width: 420, height: 520), display: true);
        MenuButton.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(self.ShowMenu(gesture:))));
        getMainWindow()?.delegate = self;
        SetupCursor();
        
        // init the manager
        tunnelMgr.tsChangedCallbacks.append(self.tunnelStatusDidChange);
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier);
        timeLaunched = 1;
        timer.invalidate();
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
        
        do {
            try tunnelMgr.startTunnel();
        } catch {
            dialogAlert("Tunnel Error", error.localizedDescription);
        }
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            zLog.error(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        
        self.bytesDown = 0.0;
        self.bytesUp = 0.0;
        
        UpdateList();
    }
    
    func tunnelStatusDidChange(_ status:NEVPNStatus) {
        
        TimerLabel.stringValue = "00:00.00";
        ConnectButton.isHidden = true;
        ConnectedButton.isHidden = false;
        timer.invalidate();
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
        
        switch status {
        case .connecting:
            ConnectButton.isHidden = true;
            ConnectedButton.isHidden = false;
            SpeedArea.alphaValue = 1.0;
            //connectStatus.stringValue = "Connecting..."
            //connectButton.title = "Turn Ziti Off"
            break
        case .connected:
            ConnectButton.isHidden = true;
            ConnectedButton.isHidden = false;
            SpeedArea.alphaValue = 1.0;
            //connectStatus.stringValue = "Connected"
            //connectButton.title = "Turn Ziti Off"
            break
        case .disconnecting:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            SpeedArea.alphaValue = 0.2;
            //connectStatus.stringValue = "Disconnecting..."
            break
        case .disconnected:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            SpeedArea.alphaValue = 0.2;
            //connectStatus.stringValue = "Not Connected"
            //connectButton.title = "Turn Ziti On"
            break
        case .invalid:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            SpeedArea.alphaValue = 0.2;
            //connectStatus.stringValue = "Invalid"
            break
        case .reasserting:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            SpeedArea.alphaValue = 0.2;
            //connectStatus.stringValue = "Reasserting..."
            //connectButton.isEnabled = false
            break
        @unknown default:
            zLog.warn("Unknown tunnel status")
            break
        }
        self.UpdateList();
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        UpdateList();
    }
    
    func onRemovedId(_ idString: String) {
        UpdateList();
    }
    
    @IBAction func AddId(_ sender: Any) {
        AddIdentity();
    }
    
    @IBAction func AddIdentity(_ sender: NSClickGestureRecognizer) {
        AddIdentity();
    }
    
    @objc func ShowMenu(gesture : NSClickGestureRecognizer) {
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let mainMenu = storyBoard.instantiateController(withIdentifier: "MainMenuScreen") as! MenuScreen;
        self.presentAsSheet(mainMenu);
    }
    
    func getMainWindow() -> NSWindow? {
        for window in NSApplication.shared.windows {
            if window.className == "NSWindow" && window.title == appName {
                return window
            }
        }
        return nil
    }
    
    @objc func showPanel(_ sender: Any?) {
        if let window = getMainWindow() {
            window.deminiaturize(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(self)
        return false
    }
    
    @objc func showInDock(_ sender: Any?) {
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
            if getMainWindow()?.isVisible ?? false {
                DispatchQueue.main.async { self.showPanel(self) }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    @IBAction func Connect(_ sender: NSClickGestureRecognizer) {
        timer.invalidate();
        TimerLabel.stringValue = "00:00.00";
        ConnectButton.isHidden = true;
        ConnectedButton.isHidden = false;
        do {
            try tunnelMgr.startTunnel();
            timeLaunched = 1;
            timer.invalidate();
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
        } catch {
            dialogAlert("Tunnel Error", error.localizedDescription);
        }
    }
    
    @IBAction func Disconnect(_ sender: NSClickGestureRecognizer) {
        timer.invalidate();
        TimerLabel.stringValue = "00:00.00";
        UpSpeed.stringValue = "0.0";
        UpSpeedSize.stringValue = "bps";
        DownSpeed.stringValue = "0.0";
        DownSpeedSize.stringValue = "bps";
        ConnectButton.isHidden = false;
        ConnectedButton.isHidden = true;
        tunnelMgr.stopTunnel();
    }
    
    @objc func UpdateTimer() {
        let formatter = DateComponentsFormatter();
        formatter.allowedUnits = [.hour, .minute, .second];
        formatter.unitsStyle = .positional;
        formatter.zeroFormattingBehavior = .pad;
        
        let speedFormetter = NumberFormatter();
        speedFormetter.numberStyle = .decimal;
        speedFormetter.maximumFractionDigits = 1;
        speedFormetter.minimumFractionDigits = 1;
        
        bytesUp = Float.random(in: 0.8 ... 4500000000);
        bytesDown = bytesUp*1000;
        
        var upSize = "bps";
        var upSpeed = bytesUp;
        let gigs:Float = (1024*1024);
        print("\(bytesUp) \(gigs)");
        if (upSpeed>gigs) {
            upSize = "gps";
            upSpeed = upSpeed/gigs;
        } else {
            if (upSpeed>1024) {
                upSize = "mps";
                upSpeed = upSpeed/1024;
            }
        }
        UpSpeed.stringValue = speedFormetter.string(from: NSNumber(value: upSpeed)) ?? "0.0";
        UpSpeedSize.stringValue = upSize;
        
        var downSize = "bps";
        var downSpeed = bytesDown;
        if (downSpeed>gigs) {
            downSize = "gps";
            downSpeed = downSpeed/gigs;
        } else {
            if (downSpeed>1024) {
                downSize = "mps";
                downSpeed = downSpeed/1024;
            }
        }
        DownSpeed.stringValue = speedFormetter.string(from: NSNumber(value: downSpeed)) ?? "0.0";
        DownSpeedSize.stringValue = downSize;

        TimerLabel.stringValue = formatter.string(from: TimeInterval(timeLaunched))!;
        timeLaunched += 1;
    }
    
    /* Jeremys Methods */
    
    func SetupCursor() {
        let items = [AddButton, AddIdButton, ConnectButton, ConnectedButton, MenuButton];
        
        pointingHand = NSCursor.pointingHand;
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        }

        arrow = NSCursor.arrow
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
        }
    }
    
    @objc func GoToDetails(gesture : GoToDetailGesture) {
        let index = gesture.indexValue;
        
        let storyBoard : NSStoryboard = NSStoryboard(name: "MainUI", bundle:nil);
        let detailView = storyBoard.instantiateController(withIdentifier: "IdentityDetail") as! IdentityDetailScreen;
        
        detailView.identity = zidMgr.zids[index ?? 0];
        detailView.dash = self;
        detailView.zidMgr = self.zidMgr;
        
        self.presentAsSheet(detailView);
    }
    
    func UpdateList() {
        
        IdentityList.horizontalScrollElasticity = .none;
        let idListView = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 500));
        idListView.orientation = .vertical;
        idListView.spacing = 2;
        //if IdView.subviews != nil {
        //for view in IdentityList.subviews {
        //    view.removeFromSuperview();
        //}
        //}
        var index = 0;
        for identity in zidMgr.zids {
            
            let clickGesture = GoToDetailGesture(target: self, action: #selector(self.GoToDetails(gesture:)));
            clickGesture.indexValue = index;
            
            let clickGesture2 = GoToDetailGesture(target: self, action: #selector(self.GoToDetails(gesture:)));
            clickGesture2.indexValue = index;
            
            let clickGesture3 = GoToDetailGesture(target: self, action: #selector(self.GoToDetails(gesture:)));
            clickGesture3.indexValue = index;
            
            // First Column of Identity Item Renderer
            let toggler = NSSwitch(frame: CGRect(x: 0, y: 0, width: 75, height: 22));
            toggler.heightAnchor.constraint(equalToConstant: 22).isActive = true;
            let connectLabel = NSText();
            
            connectLabel.isEditable = false;
            connectLabel.isSelectable = false;
            connectLabel.alignment = .center;
            connectLabel.frame.size.height = 20;
            connectLabel.font = NSFont(name: "Open Sans", size: 10);
            connectLabel.textColor = NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1.0);
            connectLabel.backgroundColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.00);
            
            toggler.isEnabled = identity.isEnrolled;
            if (identity.isEnabled) {
                toggler.state = .on;
            } else {
                toggler.state = .off;
            }
            toggler.tag = index;
            toggler.addGestureRecognizer(clickGesture);
            
            if (identity.isEnrolled) {
                if (identity.isEnabled) {
                    connectLabel.string = "connected";
                } else {
                    connectLabel.string = "disconnected";
                }
            } else {
                connectLabel.string = "not enrolled";
            }
            
            let col1 = NSStackView(views: [toggler,connectLabel]);
            col1.frame = CGRect(x: 0, y: 0, width: 75, height: 50);
            
            col1.distribution = .fillProportionally;
            col1.alignment = .centerX;
            col1.spacing = 0;
            col1.orientation = .vertical;
            col1.edgeInsets.top = 8;
            col1.widthAnchor.constraint(equalToConstant: 75).isActive = true;
            col1.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            
            // Label Column of Identity Item Renderer
            let idName = NSText();
            
            idName.font = NSFont(name: "Open Sans", size: 16);
            idName.textColor = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00);
            idName.heightAnchor.constraint(equalToConstant: 22).isActive = true;
            idName.string = String(String(identity.name).prefix(10));
            idName.isEditable = false;
            idName.isSelectable = false;
            idName.backgroundColor = NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.00);
            
            let idServer = NSText();
            idServer.font = NSFont(name: "Open Sans", size: 10);
            idServer.textColor = NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1.0);
            idServer.frame.size.height = 20;
            idServer.isEditable = false;
            idServer.isSelectable = false;
            idServer.string = identity.czid?.ztAPI ?? "no network";
            idServer.backgroundColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.00);
            
            let col2 = NSStackView(views: [idName, idServer]);
            col2.frame = CGRect(x: 0, y: 0, width: 200, height: 50);
            col2.distribution = .fill;
            col2.alignment = .leading;
            col2.spacing = 0;
            col2.frame.size.width = 120;
            col2.orientation = .vertical;
            col2.edgeInsets.top = 8;
            col2.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            col2.widthAnchor.constraint(equalToConstant: 200).isActive = true;
            col2.addGestureRecognizer(clickGesture2);
            
            
            // Count column for the item renderer
            
            //let circleView = NSView();
            //circleView.wantsLayer = true;
            //circleView.layer?.cornerRadius = 7;
            //circleView.layer?.backgroundColor = NSColor(named: "PrimaryColor")?.cgColor;
            
            //let serviceCountFrame = NSView();
            //serviceCountFrame.frame = CGRect(x: 0, y: 0, width: 50, height: 30);
            //serviceCountFrame.addSubview(circleView);
            
            let idServiceCount = NSText();
            idServiceCount.alignment = .center;
            idServiceCount.font = NSFont(name: "Open Sans", size: 16);
            idServiceCount.textColor = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00);
            idServiceCount.heightAnchor.constraint(equalToConstant: 22).isActive = true;
            idServiceCount.string = String(identity.services.count);
            idServiceCount.isEditable = false;
            idServiceCount.isSelectable = false;
            idServiceCount.backgroundColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.00);
            
            let serviceLabel = NSText();
            serviceLabel.alignment = .center;
            serviceLabel.string = "services";
            serviceLabel.frame.size.height = 20;
            serviceLabel.isEditable = false;
            serviceLabel.isSelectable = false;
            serviceLabel.addGestureRecognizer(clickGesture);
            serviceLabel.font = NSFont(name: "Open Sans", size: 10);
            serviceLabel.textColor = NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1.00);
            idServiceCount.heightAnchor.constraint(equalToConstant: 20).isActive = true;
            serviceLabel.backgroundColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.00);
            
            //serviceCountFrame.addSubview(idServiceCount);
            
            let col3 = NSStackView(views: [idServiceCount, serviceLabel]);
            col3.frame = CGRect(x: 0, y: 0, width: 50, height: 50);
            col3.distribution = .gravityAreas;
            col3.alignment = .centerX;
            col3.spacing = 0;
            col3.orientation = .vertical;
            col3.edgeInsets.top = 8;
            col3.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            col3.addGestureRecognizer(clickGesture3);
            col3.widthAnchor.constraint(equalToConstant: 50).isActive = true;
            
            // Arrow image for Item Renderer
            
            let arrowImage = NSImage(named: "next");
            let arrowView = NSImageView();
            arrowView.frame = CGRect(x: 10, y: 10, width: 10, height: 10);
            arrowView.imageScaling = .scaleProportionallyUpOrDown;
            arrowView.image = arrowImage;
            arrowView.widthAnchor.constraint(equalToConstant: 20).isActive = true;
            arrowView.heightAnchor.constraint(equalToConstant: 20).isActive = true;
            
            let col4 = NSStackView(views: [arrowView]);
            col4.frame = CGRect(x: 0, y: 0, width: 30, height: 50);
            col4.distribution = .fillProportionally;
            col4.alignment = .centerX;
            col4.spacing = 0;
            col4.orientation = .vertical;
            col4.addGestureRecognizer(clickGesture);
            idServiceCount.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            col4.widthAnchor.constraint(equalToConstant: 30).isActive = true;
            
            let items = [col2, col3, col4];
            
            pointingHand = NSCursor.pointingHand;
            for item in items {
                item.addCursorRect(item.bounds, cursor: pointingHand!);
            }
            
            pointingHand!.setOnMouseEntered(true);
            for item in items {
                item.addTrackingRect(item.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
            }

            arrow = NSCursor.arrow
            for item in items {
                item.addCursorRect(item.bounds, cursor: arrow!);
            }
            
            arrow!.setOnMouseExited(true)
            for item in items {
                item.addTrackingRect(item.bounds, owner: arrow!, userData: nil, assumeInside: true);
            }
            

            // Put all the columns into the parent frames
            
            let renderer = NSStackView(views: [col1,col2,col3,col4]);
            renderer.orientation = .horizontal;
            renderer.distribution = .fillProportionally;
            //renderer.backgroundColor = NSColor(red: 0.05, green: 0.06, blue: 0.13, alpha: 1.00);
            renderer.alignment = .centerY;
            //renderer.translatesAutoresizingMaskIntoConstraints = true;
            renderer.spacing = 0;
            renderer.frame = CGRect(x: 0, y: CGFloat((index*50)+(index*2)), width: view.frame.size.width, height: 50);

            //IdentityList.addSubview(renderer);
            idListView.addSubview(renderer);
            index = index + 1;
        }
        let clipView = FlippedClipView();
        clipView.drawsBackground = false;
        IdentityList.contentView = clipView
        clipView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          clipView.leftAnchor.constraint(equalTo: IdentityList.leftAnchor),
          clipView.rightAnchor.constraint(equalTo: IdentityList.rightAnchor),
          clipView.topAnchor.constraint(equalTo: IdentityList.topAnchor),
          clipView.bottomAnchor.constraint(equalTo: IdentityList.bottomAnchor)
        ]);
        idListView.frame = CGRect(x: 0, y: 0, width: view.frame.size.width, height: CGFloat(((50*index)+(2*index))+2));
        IdentityList.documentView = idListView;
        
        IdentityList.frame.size.height = CGFloat(index*50);
        let height = 520 + (index*50);
        guard let appWindow = NSApplication.shared.mainWindow else { return }
        self.view.window?.setFrame(NSRect(x:1024, y:-150, width: 420, height: height), display: true);
        //IdentityList.contentSize.height = CGFloat(index*72);
    }
    
    
    /* Daves Methods */
    
    func dialogAlert(_ msg:String, _ text:String? = nil) {
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText =  text ?? ""
        alert.alertStyle = NSAlert.Style.critical
        alert.runModal()
    }
    
    func dialogOKCancel(question: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    func AddIdentity() {
        guard let window = view.window else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jwt"]
        panel.title = "Select Enrollment JWT file"
        
        panel.beginSheetModal(for: window) { (result) in
            //DispatchQueue(label: "JwtLoader").async {
                if result == NSApplication.ModalResponse.OK {
                    do {
                        try self.zidMgr.insertFromJWT(panel.urls[0], at: 0)
                        DispatchQueue.main.async {
                            self.UpdateList();
                        }
                    } catch {
                        DispatchQueue.main.async {
                            panel.orderOut(nil)
                            self.dialogAlert("Unable to add identity", error.localizedDescription)
                        }
                    }
                }
            //}
        }
    }
    
    static func freshController() -> DashboardScreen {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main.UI"), bundle: nil);
        let identifier = NSStoryboard.SceneIdentifier("Dashboard");
        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? DashboardScreen else {
            fatalError("Controller Not Found")
        }
        return viewcontroller;
    }
    
}

