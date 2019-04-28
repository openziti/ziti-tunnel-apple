//
//  TunnelMgr.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/12/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation
import NetworkExtension

class TunnelMgr: NSObject {
    var tpm:NETunnelProviderManager?
    var tunnelRestarting = false
    
    typealias TunnelStateChangedCallback = ((NEVPNStatus)->Void)
    var tsChangedCallbacks:[TunnelStateChangedCallback] = []
    
    var status:NEVPNStatus {
        get {
            if let status = tpm?.connection.status { return status }
            return .invalid
        }
    }
    
    static let shared = TunnelMgr()
    private override init() {}
    deinit { NotificationCenter.default.removeObserver(self) }
    
    typealias LoadCompletionHandler = (NETunnelProviderManager?, Error?) -> Void
    func loadFromPreferences(_ bid:String, completionHandler: LoadCompletionHandler? = nil) {
        var tpm = NETunnelProviderManager()
        NETunnelProviderManager.loadAllFromPreferences { [weak self] savedManagers, error in
            if let error = error {
                NSLog(error.localizedDescription)
                completionHandler?(nil, error)
                return
            }
            
            if let savedManagers = savedManagers, savedManagers.count > 0 {
                tpm = savedManagers[0]
            }
            
            tpm.loadFromPreferences { error in
                if let error = error {
                    NSLog(error.localizedDescription)
                    completionHandler?(nil, error)
                    return
                }
                
                // This won't happen unless first time run and no profile preference has been imported
                if tpm.protocolConfiguration == nil {
                    
                    let providerProtocol = NETunnelProviderProtocol()
                    providerProtocol.providerBundleIdentifier = bid
                    
                    let defaultProviderConf = ProviderConfig()
                    providerProtocol.providerConfiguration = defaultProviderConf.createDictionary()
                    providerProtocol.serverAddress = defaultProviderConf.ipAddress
                    providerProtocol.username = defaultProviderConf.username
                    
                    tpm.protocolConfiguration = providerProtocol
                    tpm.localizedDescription = defaultProviderConf.localizedDescription
                    tpm.isEnabled = true
                    
                    tpm.saveToPreferences { error in
                        if let error = error {
                            NSLog(error.localizedDescription)
                        } else {
                            NSLog("Saved successfully. Re-loading preferences")
                            // ios hack per apple forums (else NEVPNErrorDomain Code=1)
                            tpm.loadFromPreferences { error in
                                NSLog("Re-loaded preferences, error=\(error != nil)")
                            }
                        }
                    }
                }
                
                // Get notified when tunnel status changes
                if let tmgr = self {
                    NotificationCenter.default.removeObserver(tmgr)
                    NotificationCenter.default.addObserver(tmgr, selector:
                        #selector(TunnelMgr.tunnelStatusDidChange(_:)), name:
                        NSNotification.Name.NEVPNStatusDidChange, object: nil)
                
                    tmgr.tpm = tpm
                    completionHandler?(tpm, nil)
                    tmgr.tsChangedCallbacks.forEach { cb in cb(tpm.connection.status) }
                } else {
                    completionHandler?(nil, ZitiError("Tunnel preferencecs load fail due to retain scope"))
                }
            }
        }
    }
    
    @objc func tunnelStatusDidChange(_ notification: Notification?) {
        if tunnelRestarting == true {
            if status == .disconnected {
                tunnelRestarting = false
                try? startTunnel() // TODO: Will I regret not handling exception?
            }
            tsChangedCallbacks.forEach { cb in cb(.reasserting) }
        } else {
            tsChangedCallbacks.forEach { cb in cb(status) }
        }
    }
    
    func startTunnel() throws {
        guard let tpm = self.tpm else { return }
        if tpm.isEnabled {
            try (tpm.connection as? NETunnelProviderSession)?.startTunnel()
        } else {
            NSLog("startTunnel - tunnel not enabled.  Re-enabling and starting tunnel")
            tpm.isEnabled = true
            tpm.saveToPreferences { error in
                if let error = error {
                    NSLog(error.localizedDescription)
                } else {
                    NSLog("Saved successfully. Re-loading preferences")
                    // ios hack per apple forums (else NEVPNErrorDomain Code=1 on starting tunnel)
                    tpm.loadFromPreferences { [weak tpm] error in
                        NSLog("Re-loaded preferences, error=\(error != nil). Attempting to start")
                        do {
                            try (tpm?.connection as? NETunnelProviderSession)?.startTunnel()
                        } catch {
                            NSLog("Failed starting tunnel after re-enabling. \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    func stopTunnel() {
        (tpm?.connection as? NETunnelProviderSession)?.stopTunnel()
    }
    
    func restartTunnel() {
        if let status = tpm?.connection.status, status != .disconnected {
            NSLog("Restarting tunnel")
            tunnelRestarting = true
            stopTunnel()
        }
    }
}