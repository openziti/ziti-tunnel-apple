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
    }
    
    override func viewDidLoad() {
        Logger.initShared(Logger.APP_TAG);
        zLog.info(Version.verboseStr);
        
        zidMgr.zidStore.delegate = self;
        
        self.view.window?.setFrame(NSRect(x:0,y:0,width: 420, height: 520), display: true);
        MenuButton.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(self.ShowMenu(gesture:))));
        getMainWindow()?.delegate = self;
        SetupCursor();
        
        // init the manager
        tunnelMgr.tsChangedCallbacks.append(self.tunnelStatusDidChange)
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier)
        
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
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
        
        switch status {
        case .connecting:
            ConnectButton.isHidden = true;
            ConnectedButton.isHidden = false;
            //connectStatus.stringValue = "Connecting..."
            //connectButton.title = "Turn Ziti Off"
            break
        case .connected:
            ConnectButton.isHidden = true;
            ConnectedButton.isHidden = false;
            //connectStatus.stringValue = "Connected"
            //connectButton.title = "Turn Ziti Off"
            break
        case .disconnecting:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            //connectStatus.stringValue = "Disconnecting..."
            break
        case .disconnected:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            //connectStatus.stringValue = "Not Connected"
            //connectButton.title = "Turn Ziti On"
            break
        case .invalid:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            //connectStatus.stringValue = "Invalid"
            break
        case .reasserting:
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
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
        TimerLabel.stringValue = "00:00.00";
        ConnectButton.isHidden = true;
        ConnectedButton.isHidden = false;
        do {
            try tunnelMgr.startTunnel();
            timeLaunched = 1;
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
        } catch {
            dialogAlert("Tunnel Error", error.localizedDescription);
        }
    }
    
    @IBAction func Disconnect(_ sender: NSClickGestureRecognizer) {
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
        var downSpeed = bytesUp;
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
        
        self.presentAsSheet(detailView);
    }
    
    func UpdateList() {
        
        let idListView = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 70));
        idListView.orientation = .vertical;
        //if IdView.subviews != nil {
        //for view in IdentityList.subviews {
        //    view.removeFromSuperview();
        //}
        //}
        var index = 0;
        for identity in zidMgr.zids {
            print("Index: "+identity.name);
            
            let clickGesture = GoToDetailGesture(target: self, action: #selector(self.GoToDetails(gesture:)));
            clickGesture.indexValue = index;
            
            // First Column of Identity Item Renderer
            let toggler = NSSwitch(frame: CGRect(x: 0, y: 0, width: 75, height: 30));
            toggler.heightAnchor.constraint(equalToConstant: 30).isActive = true;
            let connectLabel = NSTextField();
            
            connectLabel.frame.size.height = 20;
            connectLabel.font = NSFont(name: "Open Sans", size: 10);
            connectLabel.textColor = NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1.0);
            
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
                    connectLabel.stringValue = "connected";
                } else {
                    connectLabel.stringValue = "disconnected";
                }
            } else {
                connectLabel.stringValue = "not enrolled";
            }
            
            
            let leadLabel1 = NSTextField(frame: CGRect(x: 0, y: 0, width: 30, height: 5));
            leadLabel1.stringValue = " ";
            
            let col1 = NSStackView(views: [leadLabel1,toggler,connectLabel]);
            
            col1.frame.size.width = 75;
            col1.distribution = .fill;
            col1.alignment = .centerX;
            col1.spacing = 0;
            col1.orientation = .vertical;
            col1.widthAnchor.constraint(equalToConstant: 75).isActive = true;
            col1.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            
            
            // Label Column of Identity Item Renderer
            let idName = NSText();
            
            idName.font = NSFont(name: "Open Sans", size: 22);
            idName.textColor = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00);
            idName.heightAnchor.constraint(equalToConstant: 30).isActive = true;
            
            print("Ziti \(index)");
            print(identity.name);
            idName.string = String(String(identity.name).prefix(10));
            
            
            let idServer = NSText();
            idServer.font = NSFont(name: "Open Sans", size: 10);
            idServer.textColor = NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1.0);
            idServer.frame.size.height = 20;
            idServer.string = identity.czid?.ztAPI ?? "no network";
            
            let leadLabel2 = NSTextField(frame: CGRect(x: 0, y: 0, width: 30, height: 5));
            leadLabel2.stringValue = " ";
            
            let col2 = NSStackView(views: [leadLabel2, idName, idServer]);
            col2.distribution = .fill;
            col2.alignment = .leading;
            col2.spacing = 0;
            col2.frame.size.width = 100;
            col2.orientation = .vertical;
            col2.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            col2.addGestureRecognizer(clickGesture);
            
            
            // Count column for the item renderer
            
            let serviceCountFrame = NSView();
            //let circlePath = NSBezierPath(arcCenter: CGPoint(x: 0, y: 15), radius: CGFloat(15), startAngle: CGFloat(0), endAngle: CGFloat(Double.pi * 2), clockwise: true);
            let shapeLayer = CAShapeLayer();
            serviceCountFrame.frame = CGRect(x: 0, y: 0, width: 50, height: 40)
            //shapeLayer.path = circlePath.cgPath;
            shapeLayer.fillColor = NSColor(named: "PrimaryColor")?.cgColor;
            
            let idServiceCount = NSText();
            idServiceCount.alignment = .center;
            idServiceCount.font = NSFont(name: "Open Sans", size: 22);
            idServiceCount.textColor = NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00)
            idServiceCount.string = String(identity.services.count);
            idServiceCount.heightAnchor.constraint(equalToConstant: 30).isActive = true;
            
            let serviceLabel = NSText();
            serviceLabel.alignment = .center;
            serviceLabel.string = "services";
            serviceLabel.frame.size.height = 20;
            serviceLabel.font = NSFont(name: "Open Sans", size: 10);
            serviceLabel.textColor = NSColor(red: 0.80, green: 0.80, blue: 0.80, alpha: 1.00)
            
            //serviceCountFrame.layer.addSublayer(shapeLayer);
            serviceCountFrame.addSubview(idServiceCount);
            
            let col3 = NSStackView(views: [idServiceCount, serviceLabel]);
            col3.frame.size.width = 50;
            col3.distribution = .fill;
            col3.alignment = .centerX;
            col3.spacing = 0;
            col3.orientation = .vertical;
            //col3.isUserInteractionEnabled = true;
            //col3.tag = index;
            col3.heightAnchor.constraint(equalToConstant: 50).isActive = true;
            col3.addGestureRecognizer(clickGesture);
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
            col4.distribution = .fillProportionally;
            col4.alignment = .centerX;
            col4.spacing = 0;
            col4.orientation = .vertical;
            //col4.isUserInteractionEnabled = true;
            //col4.tag = index;
            col4.addGestureRecognizer(clickGesture);
            col4.widthAnchor.constraint(equalToConstant: 75).isActive = true;
            

            // Put all the columns into the parent frames
            
            let renderer = NSStackView(views: [col1,col2,col3,col4]);
            renderer.orientation = .horizontal;
            renderer.distribution = .fillProportionally;
            //renderer.backgroundColor = NSColor(red: 0.05, green: 0.06, blue: 0.13, alpha: 1.00);
            renderer.alignment = .centerY;
            //renderer.translatesAutoresizingMaskIntoConstraints = true;
            renderer.spacing = 4;
            renderer.frame = CGRect(x: 0, y: CGFloat((index*70)+(index*2)), width: view.frame.size.width, height: 70);

            //IdentityList.addSubview(renderer);
            idListView.addSubview(renderer);
            index = index + 1;
        }
        IdentityList.documentView = idListView;
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
    
}

