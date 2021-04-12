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
    
    /**
     Ziti SDK Variables
     */
    let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Ziti"
    var tunnelMgr = TunnelMgr.shared;
    var zidMgr = ZidMgr();
    var identity = ZitiIdentity();
    var enrollingIds:[ZitiIdentity] = [];
    
    /**
     Cursor UI variables
     */
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    /**
     Timer and values for updating speed labels
     */
    var timer = Timer();
    var timeLaunched:Int = 0;
    private var bytesDown:Float = 0.0;
    private var bytesUp:Float = 0.0;
    
    /**
     The Screens of the application controlled by the state
     */
    var state = "dashboard";
    @IBOutlet var DashboardBox: NSBox!
    @IBOutlet var MenuBox: NSBox!
    @IBOutlet var AdvancedBox: NSBox!
    @IBOutlet var AboutBox: NSBox!
    @IBOutlet var LogLevelBox: NSBox!
    @IBOutlet var ConfigBox: NSBox!
    @IBOutlet var RecoveryBox: NSBox!
    @IBOutlet var AuthBox: NSBox!
    @IBOutlet var MFASetupBox: NSBox!
    @IBOutlet var ServiceBox: NSBox!
    @IBOutlet var DetailsBox: NSBox!
    @IBOutlet var IntroBox: NSBox!
    var allViews:[NSBox] = [];
    
    
    
    
    
    
    
    
    
    
    
    /**
     Main Dashboard Screen Functionality
     */
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
    @IBOutlet var MainView: NSView!
    @IBOutlet var ParentBox: NSBox!
    @IBOutlet var IntroView: NSView!
    @IBOutlet var LogoArea: NSStackView!
    @IBOutlet var MainArea: NSStackView!
    
    override func viewWillAppear() {
        self.view.shadow = NSShadow();
        self.view.layer?.shadowOpacity = 0.6;
        self.view.layer?.shadowColor = NSColor.black.cgColor;
        self.view.layer?.shadowOffset = NSMakeSize(0, 0);
        let rect = self.view.layer?.bounds.insetBy(dx: 30, dy: 30);
        self.view.layer?.shadowPath = CGPath(rect: rect!, transform: nil);
        self.view.layer?.shadowRadius = 13;
        
        self.view.window?.titleVisibility = .hidden;
        self.view.window?.titlebarAppearsTransparent = true;
        self.view.window?.styleMask.insert(.fullSizeContentView);
        self.view.window?.styleMask.remove(.closable);
        self.view.window?.styleMask.remove(.fullScreen);
        self.view.window?.styleMask.remove(.miniaturizable);
        self.view.window?.styleMask.remove(.resizable);
        self.view.window?.isOpaque = false;
        self.view.window?.hasShadow = false;
        self.view.window?.backgroundColor = NSColor.clear;
        self.view.window?.invalidateShadow();
        self.view.window?.isMovable = true;
        self.view.window?.isMovableByWindowBackground = true;
        self.view.window?.makeKeyAndOrderFront(self);
        
        DashboardBox.wantsLayer = true;
        DashboardBox.layer?.borderWidth = 0;
        DashboardBox.layer?.cornerRadius = 20;
        DashboardBox.layer?.masksToBounds = true;
        
        IntroView.wantsLayer = true;
        IntroView.layer?.borderWidth = 0;
        IntroView.layer?.cornerRadius = 18;
        IntroView.layer?.masksToBounds = true;
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        IntroBox.isHidden = false;
        IntroBox.alphaValue = 1;
        self.allViews =  [MenuBox,AdvancedBox,AboutBox,LogLevelBox,ConfigBox,RecoveryBox,AuthBox,MFASetupBox,ServiceBox,DetailsBox,IntroBox];
        
        Logger.initShared(Logger.APP_TAG);
        zLog.info(Version.verboseStr);
        zidMgr.zidStore.delegate = self;
        
        VersionString.stringValue = "v"+Version.str;
        
        self.view.window?.setFrame(NSRect(x:0,y:0,width: 420, height: 520), display: true);
        getMainWindow()?.delegate = self;
        
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
        SetupCursor();
        
        // Details Setup
        MFAToggle.layer?.backgroundColor = NSColor.red.cgColor;
        MFAToggle.layer?.masksToBounds = true;
        MFAToggle.layer?.cornerRadius = 10;
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 3;
            self.IntroView.animator().alphaValue = 0;
        } completionHandler: {
            self.HideAll();
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    
    /**
     Detail Screen Functionality
     */
    @IBOutlet var IdDetailCloseButton: NSImageView!
    @IBOutlet var ToggleIdentity: NSSwitch!
    @IBOutlet var IdName: NSTextField!
    @IBOutlet var IdNetwork: NSTextField!
    @IBOutlet var IdEnrolled: NSTextField!
    @IBOutlet var IdStatus: NSTextField!
    @IBOutlet var IdServiceCount: NSTextField!
    @IBOutlet var EnrollButton: NSTextField!
    @IBOutlet var ServiceList: NSScrollView!
    @IBOutlet var ForgotButton: NSTextField!
    @IBOutlet var MFAOn: NSImageView!
    @IBOutlet var MFAOff: NSImageView!
    @IBOutlet var MFARecovery: NSImageView!
    @IBOutlet var MFAToggle: NSSwitch!
    
    /**
     Show the details view and fill in the UI elements
     */
    func ShowDetails() {
        ToggleIdentity.isHidden = false;
        ForgotButton.isHidden = false;
        ServiceList.isHidden = false;
        IdServiceCount.isHidden = false;
        if (self.identity.isEnabled) {
            ToggleIdentity.state = .on;
        } else {
            ToggleIdentity.state = .off;
        }
        if (self.identity.isEnabled) {
            IdStatus.stringValue = "active";
        } else {
            IdStatus.stringValue = "inactive";
        }
        if (self.identity.isEnrolled) {
            IdEnrolled.stringValue = "enrolled";
        } else {
            IdEnrolled.stringValue = "not enrolled";
            ToggleIdentity.isHidden = true;
            ForgotButton.isHidden = true;
            ServiceList.isHidden = true;
            IdServiceCount.isHidden = true;
        }
        IdName.stringValue = self.identity.name;
        IdNetwork.stringValue = self.identity.czid?.ztAPI ?? "no network";
        IdServiceCount.stringValue = "\(self.identity.services.count) Services";
        
        MFAOn.isHidden = true; // Show is enabled and authenticated
        // MFAOff.isHidden = true; - show if enabled
        // MFARecovery.isHidden = true; - show if authenticated
            
        let serviceListView = NSStackView(frame: NSRect(x: 0, y: 0, width: self.view.frame.width-50, height: 70));
        serviceListView.orientation = .vertical;
        serviceListView.spacing = 2;
        var baseHeight = 480;
        var index = 0;
        
        if (self.identity.isEnrolled) {
            let rowHeight = 50;
            for service in self.identity.services {
                let serviceName = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 14));
                let serviceUrl = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 12));
                let serviceProtocol = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 12));
                let servicePorts = NSText(frame: CGRect(x: 0, y: 0, width: self.view.frame.width-50, height: 12));
                
                serviceName.string = service.name ?? "";
                serviceUrl.string = service.addresses ?? "None";
                serviceUrl.string = service.protocols ?? "None";
                serviceUrl.string = service.portRanges ?? "None";
                
                serviceName.font = NSFont(name: "Open Sans", size: 12);
                serviceName.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00);
                serviceUrl.font = NSFont(name: "Open Sans", size: 11);
                serviceUrl.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60);
                serviceProtocol.font = NSFont(name: "Open Sans", size: 11);
                serviceProtocol.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60);
                servicePorts.font = NSFont(name: "Open Sans", size: 11);
                servicePorts.textColor = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.60);
                
                serviceName.isEditable = false;
                serviceUrl.isEditable = false;
                serviceProtocol.isEditable = false;
                servicePorts.isEditable = false;
                
                serviceName.backgroundColor = NSColor.clear;
                serviceUrl.backgroundColor = NSColor.clear;
                serviceProtocol.backgroundColor = NSColor.clear;
                servicePorts.backgroundColor = NSColor.clear;
                
                serviceName.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                serviceName.heightAnchor.constraint(equalToConstant: CGFloat(14)).isActive = true
                serviceUrl.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                serviceUrl.heightAnchor.constraint(equalToConstant: CGFloat(12)).isActive = true
                serviceProtocol.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                serviceProtocol.heightAnchor.constraint(equalToConstant: CGFloat(12)).isActive = true
                servicePorts.widthAnchor.constraint(equalToConstant: self.view.frame.width-50).isActive = true
                servicePorts.heightAnchor.constraint(equalToConstant: CGFloat(12)).isActive = true
                
                let stack = NSStackView(views: [serviceName, serviceUrl, serviceProtocol, servicePorts]);
                
                stack.edgeInsets.top = 14;
                stack.distribution = .fillProportionally;
                stack.alignment = .leading;
                stack.spacing = 0;
                stack.orientation = .vertical;
                stack.frame = CGRect(x: 0, y: CGFloat(index*rowHeight), width: view.frame.size.width-90, height: CGFloat(rowHeight));

                serviceListView.addSubview(stack);
                index = index + 1;
            }
            
            let clipView = FlippedClipView();
            clipView.drawsBackground = false;
            ServiceList.horizontalScrollElasticity = .none;
            ServiceList.contentView = clipView
            clipView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
              clipView.leftAnchor.constraint(equalTo: ServiceList.leftAnchor),
              clipView.rightAnchor.constraint(equalTo: ServiceList.rightAnchor),
              clipView.topAnchor.constraint(equalTo: ServiceList.topAnchor),
              clipView.bottomAnchor.constraint(equalTo: ServiceList.bottomAnchor)
            ]);
            
            serviceListView.frame = CGRect(x: 0, y: 0, width: view.frame.size.width-50, height: CGFloat(((rowHeight*index))));
            ServiceList.documentView = serviceListView;
            EnrollButton.isHidden = true;
        } else {
            EnrollButton.isHidden = false;
        }
        
        if (index>3) {
            index = index-2;
            baseHeight = baseHeight+(50*index);
        }
        guard var frame = self.view.window?.frame else { return };
        frame.size = NSMakeSize(CGFloat(420), CGFloat(baseHeight));
        self.view.window?.setFrame(frame, display: true);
        
        ServiceList.documentView = serviceListView;
        showArea(state: "details");
    }
    
    /**
     Connect the client and restart the timer
     */
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
    
    /**
     Disconnct the client and stop the tunnel
     */
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
    
    /**
     Toggle the state of the identity
     */
    @IBAction func Toggled(_ sender: NSClickGestureRecognizer) {
        identity.enabled = ToggleIdentity.state != .on;
        _ = zidMgr.zidStore.store(identity);
        ShowDetails();
        tunnelMgr.restartTunnel();
        self.UpdateList();
    }
    
    /**
     Forget the identity and update the main list closing the details view
     */
    @IBAction func Forget(_ sender: NSClickGestureRecognizer) {
        let text = "Deleting identity \(identity.name) (\(identity.id)) can't be undone"
        if dialogOKCancel(question: "Are you sure?", text: text) == true {
            let error = zidMgr.zidStore.remove(identity)
            guard error == nil else {
                dialogAlert("Unable to remove identity", error!.localizedDescription)
                return
            }
            UpdateList();
            Close(sender);
        }
    }
    
    /**
     Show the identity details
     */
    @objc func GoToDetails(gesture : GoToDetailGesture) {
        let index = gesture.indexValue;
        self.identity = zidMgr.zids[index ?? 0];
        ShowDetails();
    }
    
    /**
     Enroll the currnt identity
     */
    @IBAction func Enroll(_ sender: Any) {
        EnrollButton.isHidden = true;
        enrollingIds.append(identity);
        
        guard let presentedItemURL = zidMgr.zidStore.presentedItemURL else {
            self.dialogAlert("Unable to enroll \(identity.name)", "Unable to access group container");
            return;
        }
        
        let url = presentedItemURL.appendingPathComponent("\(identity.id).jwt", isDirectory:false);
        let jwtFile = url.path;
        
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async { [self] in
                    self.enrollingIds.removeAll { $0.id == identity.id }
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = zidMgr.zidStore.store(self.identity);
                        self.dialogAlert("Unable to enroll \(identity.name)", zErr != nil ? zErr!.localizedDescription : "invalid response");
                        return;
                    }
                    
                    if self.identity.czid == nil {
                        identity.czid = CZiti.ZitiIdentity(id: zidResp.id, ztAPI: zidResp.ztAPI);
                    }
                    identity.czid?.ca = zidResp.ca;
                    if zidResp.name != nil {
                        identity.czid?.name = zidResp.name;
                    }
                    
                    identity.enabled = true;
                    identity.enrolled = true;
                    _ = zidMgr.zidStore.store(identity);
                    self.tunnelMgr.restartTunnel();
                    self.ShowDetails();
                }
            }
        }
    }
    
    
    @IBAction func AuthClicked(_ sender: NSClickGestureRecognizer) {
        showArea(state: "area");
    }
    
    
    @IBAction func ShowRecoveryScreen(_ sender: NSClickGestureRecognizer) {
        showArea(state: "recovery");
    }
    
    @IBAction func ToggleMFA(_ sender: NSClickGestureRecognizer) {
        if (MFAToggle.state == .off) {
            // prompty to setup MF
            
            showArea(state: "mfa");
            
            // Send in the url and secret code to setup MFA
            
        } else {
            // prompt to turn off mfa if it is enabled
            showArea(state: "auth");
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    /**
     Main Menu Screen Functionality
     */
    @IBOutlet var AdvancedButton: NSStackView!
    @IBOutlet var AboutButton: NSStackView!
    @IBOutlet var FeedbackButton: NSStackView!
    @IBOutlet var SupportButton: NSStackView!
    @IBOutlet var DetachButton: NSStackView!
    @IBOutlet var QuitButton: NSTextField!
    
    /**
     Close the app down
     */
    @IBAction func Exit(_ sender: NSClickGestureRecognizer) {
        exit(0);
    }
    
    @IBAction func ShowFeedback(_ sender: NSClickGestureRecognizer) {
        
    }
    
    @IBAction func ShowSupport(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://openziti.discourse.group")!;
        NSWorkspace.shared.open(url);
    }
    
    
    @IBAction func DetachApp(_ sender: NSClickGestureRecognizer) {
        
    }
    
    @IBAction func ShowAbout(_ sender: NSClickGestureRecognizer) {
        showArea(state: "about")
    }
    
    @IBAction func ShowAdvanced(_ sender: NSClickGestureRecognizer) {
        showArea(state: "advanced")
    }
    
    
    
    
    
    
    
    
    
    
    /**
     About Screen functionality
     */
    @IBOutlet var AboutBackButton: NSImageView!
    @IBOutlet var AboutCloseButton: NSImageView!
    @IBOutlet var PrivacyButton: NSStackView!
    @IBOutlet var TermsButton: NSStackView!
    @IBOutlet var VersionString: NSTextField!
    
    @IBAction func OpenPrivacy(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://netfoundry.io/privacy")!;
        NSWorkspace.shared.open(url);
    }
    
    @IBAction func OpenTerms(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://netfoundry.io/terms")!;
        NSWorkspace.shared.open(url);
    }
    
    @IBAction func DoAboutBack(_ sender: NSClickGestureRecognizer) {
        Close(sender);
    }
    
    @IBAction func DoAboutClose(_ sender: NSClickGestureRecognizer) {
        Close(sender);
        Close(sender);
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
    
    @IBAction func ShowMenu(_ sender: NSClickGestureRecognizer) {
        showArea(state: "menu");
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
    
    func UpdateList() {
        
        IdentityList.horizontalScrollElasticity = .none;
        IdentityList.horizontalScroller = .none;
        let idListView = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 500));
        idListView.orientation = .vertical;
        idListView.spacing = 2;
        //if IdView.subviews != nil {
        //for view in IdentityList.subviews {
        //  view.removeFromSuperview();
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
        let height = 720 + (index*50);
        self.ParentView.window?.setFrame(NSRect(x:0.0, y: 0.0, width: 420, height: 2014), display: true);
        self.DashboardBox.window?.setFrame(NSRect(x:0.0, y: 0.0, width: 420, height: 2014), display: true);
        self.MainView.window?.setFrame(NSRect(x:0.0, y: 0.0, width: 420, height: 2014), display: true);
        self.MainArea.window?.setFrame(NSRect(x:0.0, y: 0.0, width: 420, height: 2014), display: true);
        self.view.window?.center()
        self.view.window?.aspectRatio = NSSize(width: 420, height: 2014)
        self.view.window?.minSize = NSSize(width: 420, height: 2014)
        self.view.window?.setFrameAutosaveName("Main Window")
        self.view.window?.makeKeyAndOrderFront(nil)
        
        //IdentityList.contentSize.height = CGFloat(index*72);
    }
    
    
    
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
    
    
    
    
    
    
    
    
    
    
    /**
     Hide and kill the clickability of all fields
     */
    func HideAll() {
        for view in allViews {
            view.isHidden = true;
            view.alphaValue = 1;
            view.shadow = .none;
        }
    }
    
    /**
     Return the current view area for the state we are in
     */
    func GetStateView() -> NSView {
        var view = MenuBox;
        
        switch self.state {
        case "details":
            view = DetailsBox;
        case "menu":
            view = MenuBox;
        case "advanced":
            view = AdvancedBox;
        case "about":
            view = AboutBox;
        case "config":
            view = ConfigBox;
        case "mfa":
            view = MFASetupBox;
        case "loglevel":
            view = LogLevelBox;
        case "auth":
            view = AuthBox;
        case "recovery":
            view = RecoveryBox;
        default:
            view = MenuBox;
        }
        
        return view!;
    }
    
    /**
     Show the area defined by the state we are in
     */
    func showArea(state: String) {
        self.state = state;
        
        let view = GetStateView();
        view.isHidden = false;
        view.alphaValue = 0;
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.5
            view.animator().alphaValue = 1
        } completionHandler: {
            view.alphaValue = 1;
            view.isHidden = false;
        }
    }
    
    /**
     Close the current view
     */
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        let view = GetStateView();
        if (state=="about"||state=="advanced") {
            state = "menu";
        } else if (state=="config"||state=="loglevel") {
            state = "advanced";
        } else if (state=="mfa"||state=="recovery") {
            state = "details";
        } else {
            state = "dashboard";
        }
        
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            view.animator().alphaValue = 0
        } completionHandler: {
            view.alphaValue = 1;
            view.isHidden = true;
        }
    }
    
    /**
        Setup the cursor for rollover state to fade the elements and show the pointer cursor
     */
    func SetupCursor() {
        let items = [AddButton, AddIdButton, ConnectButton, ConnectedButton, MenuButton,
                     IdDetailCloseButton, EnrollButton, ForgotButton, ToggleIdentity, MFAToggle, MFAOff, MFARecovery, QuitButton, AdvancedButton, AboutButton, FeedbackButton, SupportButton, DetachButton,
                     AboutBackButton, AboutCloseButton, PrivacyButton, TermsButton];
        
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
    
}

