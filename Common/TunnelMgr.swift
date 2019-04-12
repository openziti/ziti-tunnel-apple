//
//  TunnelMgr.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/12/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation
import NetworkExtension

// TODO: shared observer, tunnel start/stop/restart
class TunnelMgr: NSObject {
    var tpm:NETunnelProviderManager?
    var tunnelRestarting = false
    var onTunnelStatusChanged:((NEVPNStatus)->Void)? = nil
    
    var status:NEVPNStatus {
        get {
            if let status = tpm?.connection.status { return status }
            return .invalid
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
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
                                NSLog("re-loaded preferences, error=\(error != nil)")
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
                    tmgr.onTunnelStatusChanged?(tpm.connection.status)
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
            onTunnelStatusChanged?(.reasserting)
        } else {
            onTunnelStatusChanged?(status)
        }
    }
    
    func startTunnel() throws {
        try (tpm?.connection as? NETunnelProviderSession)?.startTunnel()
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
