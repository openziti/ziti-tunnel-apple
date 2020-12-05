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
                zLog.error(error.localizedDescription)
                completionHandler?(nil, error)
                return
            }
            
            if let savedManagers = savedManagers, savedManagers.count > 0 {
                tpm = savedManagers[0]
            }
            
            tpm.loadFromPreferences { error in
                if let error = error {
                    zLog.error(error.localizedDescription)
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
                            zLog.error(error.localizedDescription)
                        } else {
                            zLog.info("Saved successfully. Re-loading preferences")
                            // ios hack per apple forums (else NEVPNErrorDomain Code=1)
                            tpm.loadFromPreferences { error in
                                zLog.error("Re-loaded preferences, error=\(error != nil)")
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
                try? startTunnel()
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
            zLog.warn("startTunnel - tunnel not enabled.  Re-enabling and starting tunnel")
            tpm.isEnabled = true
            tpm.saveToPreferences { error in
                if let error = error {
                    zLog.error(error.localizedDescription)
                } else {
                    zLog.info("Saved successfully. Re-loading preferences")
                    // ios hack per apple forums (else NEVPNErrorDomain Code=1 on starting tunnel)
                    tpm.loadFromPreferences { [weak tpm] error in
                        zLog.error("Re-loaded preferences, error=\(error != nil). Attempting to start")
                        do {
                            try (tpm?.connection as? NETunnelProviderSession)?.startTunnel()
                        } catch {
                            zLog.error("Failed starting tunnel after re-enabling. \(error.localizedDescription)")
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
            zLog.info("Restarting tunnel")
            tunnelRestarting = true
            stopTunnel()
        }
    }
}
