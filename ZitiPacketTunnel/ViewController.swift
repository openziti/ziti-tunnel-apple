//
//  ViewController.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Cocoa
import NetworkExtension
import JWTDecode

class ViewController: NSViewController, NSTextFieldDelegate {

    @IBOutlet weak var connectButton: NSButton!
    @IBOutlet weak var connectStatus: NSTextField!
    @IBOutlet weak var editBox: NSBox!
    @IBOutlet weak var ipAddressText: NSTextField!
    @IBOutlet weak var subnetMaskText: NSTextField!
    @IBOutlet weak var mtuText: NSTextField!
    @IBOutlet weak var dnsServersText: NSTextField!
    @IBOutlet weak var matchedDomainsText: NSTextField!
    @IBOutlet weak var revertButton: NSButton!
    @IBOutlet weak var applyButton: NSButton!
    
    static let providerBundleIdentifier = "com.ampifyllc.ZitiPacketTunnel.PacketTunnelProvider"
    var tunnelProviderManager: NETunnelProviderManager = NETunnelProviderManager()
    
    private func initTunnelProviderManager() {
        
        //let delegate = NSApplication.shared.delegate as! AppDelegate
       let jwt = try! decode(jwt: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE1MjgxNDUzNjIsImFwaUJhc2VVcmwiOiJodHRwczovL3ppdGktZGV2LWNvbnRyb2xsZXIwMS5sb2NhbGhvc3Q6MTA4MC8iLCJlbnJvbGxtZW50VXJsIjoiaHR0cHM6Ly96aXRpLWRldi1jb250cm9sbGVyMDEubG9jYWxob3N0OjEwODAvZW5yb2xsP21ldGhvZD1vdHQmdG9rZW49ZWU4Y2VhMTAtNjQ0YS0xMWU4LWEyZDgtNTkzMWIwZDMwMzRhIiwibWV0aG9kIjoib3R0IiwidG9rZW4iOiJlZThjZWExMC02NDRhLTExZTgtYTJkOC01OTMxYjBkMzAzNGEiLCJ2ZXJzaW9ucyI6eyJhcGkiOiIxLjAuMCIsImVucm9sbG1lbnRBcGkiOiIxLjAuMCJ9LCJyb290Q2EiOiItLS0tLUJFR0lOIENFUlRJRklDQVRFLS0tLS1cbk1JSUZtakNDQTRLZ0F3SUJBZ0lKQU1rd04zaERXUzBNTUEwR0NTcUdTSWIzRFFFQkN3VUFNRm94Q3pBSkJnTlZcbkJBWVRBbFZUTVFzd0NRWURWUVFJREFKT1F6RVRNQkVHQTFVRUNnd0tUbVYwUm05MWJtUnllVEVwTUNjR0ExVUVcbkF3d2dUbVYwUm05MWJtUnllU0JhYVhScElFbHVkR1Z5Ym1Gc0lGSnZiM1FnUTBFd0hoY05NVGd3TlRNd01UUTBcbk5UTXlXaGNOTXpnd05USTFNVFEwTlRNeVdqQmFNUXN3Q1FZRFZRUUdFd0pWVXpFTE1Ba0dBMVVFQ0F3Q1RrTXhcbkV6QVJCZ05WQkFvTUNrNWxkRVp2ZFc1a2Nua3hLVEFuQmdOVkJBTU1JRTVsZEVadmRXNWtjbmtnV21sMGFTQkpcbmJuUmxjbTVoYkNCU2IyOTBJRU5CTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUFcbjBocS9UMnpnSG5kYUxVK1FuUHVDZDdLeDJrdmJNRHY4UTBFTUpJWHRnVnpjeDRRL0MycXkxQ3JQY1hCWThnb1lcbnBhVTBneTZpK1hDZDQyU2lhSHQ4djRLb2Rka0c1WTVOcXhPeExLbWc5bFA4M0lpY20zVGtyQkpPNHlsclFmMjFcbitYVHRUbGpkbGRjRmtXd0huWk1vcHVpMjNpWVh0M0Roa1Y2MVZ5SU1pS0ZqOWhuS3V6Tnd5amhqZnpXWFQ3a0lcbmhYZkNhN1JGTXdvZmlCbFRjVzZmeXVBZ000TUVndDlIMGxVRE9LYzB5QWZ5YjZ0bWNPNkoxS2kzaWh1bWZ0bmhcbnNobHhMd2w2ZnlLTXNWQjdVNGpGaG1iRy84NmsyS2Fwa3dBREQyRUJLNkpnVkdyRUxSSUpaWjVrREhmWTUrOVhcbk9OY2l3NUtBV2YyTXZpQlZQSlFxaURCZFZPV25sOEREUXBNaDlTVEFudm5aSm1nY25SQkhnTklBRGlxRHhqSTNcbk5MTXN0UU01MmdBTkJxMllESVBVb0o0SzRtQlFaOGRUV3NEcEhnWEF3RFJHSzN3czc4NTRMWUpKTUYraWZ3OGVcbmtCckRzYmQzK1ZqK0s1azFpU1ZSaVBrYXBZU3FPaUZpR3lsVVVGcXNsaURPaW1FVEtVOHFvRm03bklMeTg0RWJcbmRNNVhzRm9mS2xPQkhHTEppQ3FkTFJXemtMdTI2bW0yL25zRmNvZGx0OXZCVlcrdzVtTGlVREU1T0hndGtTL2dcbmJMdHZvcXdTQXIxT3dJQ0F5Mlp5bjNaaFc3a1VJeWZwRjl0di9GQVJtNzc0MGwyZ3dHMzVNN0M5Nm1IUlRjK2tcbmdMNkJYc1JYbmNoSG1YVWh2WStwN0xZLzE2YTBMSmxvVXB5UXhnQU55YVVDQXdFQUFhTmpNR0V3SFFZRFZSME9cbkJCWUVGTlF4VDY4RjZYaDc4RVh2QWZvN05IbzZ1M256TUI4R0ExVWRJd1FZTUJhQUZOUXhUNjhGNlhoNzhFWHZcbkFmbzdOSG82dTNuek1BOEdBMVVkRXdFQi93UUZNQU1CQWY4d0RnWURWUjBQQVFIL0JBUURBZ0dHTUEwR0NTcUdcblNJYjNEUUVCQ3dVQUE0SUNBUURINkM1UzZINFF5U0FtcHIxL0lBZklzK05KVVY1L2M3RUhPeXNlRi91SGlMU2lcbnZaMzQvWEYvcWNXWVY2SkJ4a21XMGdrdk1vQjQ1aXhlaERtNVNmQ29QcnA5MG1ET2IvTUtWcGdPWEFEdU1tcGJcbjdaS2dXL0ZSelMrOW1LL2xpUDlNRzA0SFB5b2JGVVJyRzd4cGRsTlY2elVOdEtaU2wyczg0Y2xBRXNOa3F4S3BcbjhjclJTN2NUaWJIaFpyYm0wd21RZHU2eU96aUZEVzJ3c0szN0lOdmRPTWtvN0RyTTFvQkVmR0tQUGhPV0xvc21cblJpb3R5MjRqR3U5TnZYZmVQZk1UTFZsdlFyMnFxN3BMMUF1U1MrcGJVc3FNV1Z1T2x3SzRXeHFSUnFVbktTRGFcbjlrNkRDdEZ4cjduWXNBNHM1eGZ3RFRYcFB2VzcvWUoyaXlqZjRkRDZ5SXdzRUNOOFFNNUhicmVUL2NuZUtoSGlcbkNtRlI5OTNIM2p5UVhUU0xRQnJiQ0l2MmxNRHdrNklONUZTbkxSTExCK2lZK3RPL1ltYUJNSDBwVExwamg2ckxcbkRiNkRmc1lHc1oreEREVGJJT2ZkcTVBRWVEUStNUzNRTmxFcjRhR1MvTmM3Sm96eG15YmRoeDFXayswdmVxbG5cblBNNDk3QjNvMSttN1RJWC9RY1VoYzVYRkNDUStyL1V0bHVmdlVHYkZJVGgvUjdNK0RnMlBFWThJUHZQZEV2emRcbkFtZndMeTNGLzJXU2Ira0RkR3hYRk1RbUIzcWpGVlhoZ05OTjNOMWpTeDhWYnZOWERrK2U1UG91REdpTjROMkpcblNpN0lqcHVtalJwZ05qRXVvWGJkYndBZzZ6V1pxcFdpNmRrNEc2MkVrZXZ1STlYV3liaGg0ZUpLOFRsSCtRPT1cbi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS1cbiIsImlhdCI6MTUyNzcxMzM2Mn0.ZnUIX44SV3sGg9kxQSDjwtpowJfq8Jc28kfjBGqyy2DFmmsmGvRS6Z80bEKOklAblpEiMFuudE2PR3aIlFpUy0bpBODHvIb1lb11TbfxMmwdaxmZnOXah9WSX9hPM3Z5r7Q51__5Aoee19K5AvivTWCAMMWV6ZX5G-qewQ9G63SjfhLoDHYK4njXQXRC2AusqC2YzifWmP7Ynfz8DxeVMtHsb4OOctO3pTqY2v67vnBL5nJbCAukm1DDYA_gZZOLsK5xCIU2d8EF0TMAMzWactRvqGdwMCw00pO1k0um5b3nnI4E-STL9pjIgWADossWia0Brwo-rblGfPWW0qJnjA")
        //print(jwt)
        print("API Base URL: \(jwt.body["apiBaseUrl"] as! String)")
        print("Enrollment URL: \(jwt.body["enrollmentUrl"] as! String)")
        print("Method: \(jwt.body["method"] as! String)")
        print("Root CA: \(jwt.body["rootCa"] as! String)")

        NETunnelProviderManager.loadAllFromPreferences { (savedManagers: [NETunnelProviderManager]?, error: Error?) in
            
            //
            // Find our manager (there should only be one, since we only are managing a single
            // extension).  If error and savedManagers are both nil that means there is no previous
            // configuration stored for this app (e.g., first time run, no Preference Profile loaded)
            // Note self.tunnelProviderManager will never be nil.
            //
            if let error = error {
                NSLog(error.localizedDescription)
                // keep going - we still might need to set default values...
            }
            
            if let savedManagers = savedManagers {
                if savedManagers.count > 0 {
                    self.tunnelProviderManager = savedManagers[0]
                }
            }
            
            self.tunnelProviderManager.loadFromPreferences(completionHandler: { (error:Error?) in
                
                if let error = error {
                    NSLog(error.localizedDescription)
                }
                
                // This shouldn't happen unless first time run and no profile preference has been
                // imported, but handy for development...
                if self.tunnelProviderManager.protocolConfiguration == nil {
                    
                    let providerProtocol = NETunnelProviderProtocol()
                    providerProtocol.providerBundleIdentifier = ViewController.providerBundleIdentifier
                    
                    let defaultProviderConf = ProviderConfig()
                    providerProtocol.providerConfiguration = defaultProviderConf.createDictionary()
                    providerProtocol.serverAddress = defaultProviderConf.serverAddress
                    providerProtocol.username = defaultProviderConf.username
                    
                    self.tunnelProviderManager.protocolConfiguration = providerProtocol
                    self.tunnelProviderManager.localizedDescription = defaultProviderConf.localizedDescription
                    self.tunnelProviderManager.isEnabled = true
                    
                    self.tunnelProviderManager.saveToPreferences(completionHandler: { (error:Error?) in
                        if let error = error {
                            NSLog(error.localizedDescription)
                        } else {
                            print("Saved successfully")
                        }
                    })
                }
                
                self.updateConfigControls()
                
                // update the Connect Button label
                self.tunnelStatusDidChange(nil)
            })
        }
    }
    
    private func updateConfigControls() {
        
        self.ipAddressText.stringValue = ""
        self.subnetMaskText.stringValue = ""
        self.mtuText.stringValue = ""
        self.dnsServersText.stringValue = ""
        self.matchedDomainsText.stringValue = ""
        
        if self.tunnelProviderManager.protocolConfiguration == nil {
            return
        }
        
        let conf = (self.tunnelProviderManager.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as ProviderConfigDict

        if let ip = conf[ProviderConfig.IP_KEY] {
            self.ipAddressText.stringValue = ip as! String
        }
        
        if let subnet = conf[ProviderConfig.SUBNET_KEY] {
            self.subnetMaskText.stringValue = subnet as! String
        }
        
        if let mtu = conf[ProviderConfig.MTU_KEY] {
            self.mtuText.stringValue = mtu as! String
        }
        
        if let dns = conf[ProviderConfig.DNS_KEY] {
            self.dnsServersText.stringValue = dns as! String
        }
        
        if let matchDomains = conf[ProviderConfig.MATCH_DOMAINS_KEY] {
            self.matchedDomainsText.stringValue = matchDomains as! String
        }
        
        self.ipAddressText.becomeFirstResponder()
    }
    
    @objc func tunnelStatusDidChange(_ notification: Notification?) {
        print("Tunnel Status changed:")
        let status = self.tunnelProviderManager.connection.status
        switch status {
        case .connecting:
            print("Connecting...")
            connectStatus.stringValue = "Connecting..."
            connectButton.title = "Turn Ziti Off"
            break
        case .connected:
            print("Connected...")
            connectStatus.stringValue = "Connected"
            connectButton.title = "Turn Ziti Off"
            break
        case .disconnecting:
            print("Disconnecting...")
            connectStatus.stringValue = "Disconnecting..."
            break
        case .disconnected:
            print("Disconnected...")
            connectStatus.stringValue = "Disconnected"
            connectButton.title = "Turn Ziti On"
            break
        case .invalid:
            print("Invalid")
            break
        case .reasserting:
            print("Reasserting...")
            break
        }
    }
   
    override func viewDidLoad() {
        super.viewDidLoad()
        
        editBox.borderType = NSBorderType.lineBorder
        self.ipAddressText.delegate = self
        self.subnetMaskText.delegate = self
        self.mtuText.delegate = self
        self.dnsServersText.delegate = self
        self.matchedDomainsText.delegate = self

        initTunnelProviderManager()
        
        /* quick test...
        self.tunnelProviderManager.removeFromPreferences(completionHandler: { (error:Error?) in
            if let error = error {
                print(error)
            }
        })
         */
        
        NotificationCenter.default.addObserver(self, selector:
            #selector(ViewController.tunnelStatusDidChange(_:)), name:
            NSNotification.Name.NEVPNStatusDidChange, object: nil)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    // Occurs whenever you input first symbol after focus is here
    override func controlTextDidBeginEditing(_ obj: Notification) {
        self.revertButton.isEnabled = true
        self.applyButton.isEnabled = true
    }

    @IBAction func onApplyButton(_ sender: Any) {
        
        var dict = ProviderConfigDict()
        dict[ProviderConfig.IP_KEY] = self.ipAddressText.stringValue
        dict[ProviderConfig.SUBNET_KEY] = self.subnetMaskText.stringValue
        dict[ProviderConfig.MTU_KEY] = self.mtuText.stringValue
        dict[ProviderConfig.DNS_KEY] = self.dnsServersText.stringValue
        dict[ProviderConfig.MATCH_DOMAINS_KEY] = self.matchedDomainsText.stringValue
        
        let conf:ProviderConfig = ProviderConfig()
        if let error = conf.parseDictionary(dict) {
            // TOOO alert and get outta here
            print("Error validating conf. \(error)")
            let alert = NSAlert()
            alert.messageText = "Configuration Error"
            alert.informativeText =  error.description
            alert.alertStyle = NSAlert.Style.critical
            alert.runModal()
            return
        }
        
        (self.tunnelProviderManager.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration = conf.createDictionary()
        self.tunnelProviderManager.saveToPreferences { error in
            if let error = error {
                print("Error saving perferences \(error)")
                NSAlert(error:error).runModal()
            } else {
                if self.tunnelProviderManager.connection.status == .connected {
                    let alert = NSAlert()
                    alert.messageText = "Configuration Saved"
                    alert.informativeText =  "Will take affect on tunnel re-start"
                    alert.alertStyle = NSAlert.Style.informational
                    alert.runModal()
                }
                self.applyButton.isEnabled = false
                self.revertButton.isEnabled = false
            }
        }
        
/*        if let session = self.tunnelProviderManager.connection as? NETunnelProviderSession,
            let message = "Hello Provider".data(using: String.Encoding.utf8),
            self.tunnelProviderManager.connection.status != .invalid {
            
            do {
                try session.sendProviderMessage(message) { response in
                    if response != nil {
                        let responseString = NSString(data: response!, encoding: String.Encoding.utf8.rawValue)
                        print("Received response from the provider: \(responseString ?? "-no response-")")
                        let alert = NSAlert()
                        alert.messageText = "Ziti Packer Tunnel"
                        alert.informativeText = "Received response from the provider: \(responseString ?? "-no response-")"
                        alert.alertStyle = NSAlert.Style.informational
                        alert.runModal()
                    } else {
                        print("Got a nil response from the provider")
                    }
                }
            } catch {
                print("Failed to send a message to the provider")
            }
        }
 */
    }
    
    @IBAction func onRevertButton(_ sender: Any) {
        self.updateConfigControls()
        self.revertButton.isEnabled = false
        self.applyButton.isEnabled = false
    }
    
    @IBAction func onConnectButton(_ sender: NSButton) {
        print("onConnectButton")
        
        if (sender.title == "Turn Ziti On") {
            do {
                try self.tunnelProviderManager.connection.startVPNTunnel()
            } catch {
                print(error)
                NSAlert(error:error).runModal()
            }
        } else {
            self.tunnelProviderManager.connection.stopVPNTunnel()
        }
    }
}

