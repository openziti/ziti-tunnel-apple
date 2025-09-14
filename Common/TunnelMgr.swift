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
import CZiti

class TunnelMgr: NSObject {
    var tpm:NETunnelProviderManager?
    var tunnelRestarting = false
    var tlsuvLoggingEnabled = false
    let ipcClient = IpcAppClient()
    
    var zids:[ZitiIdentity] = []
    var zidStore = ZitiIdentityStore()
    
    typealias TunnelStateChangedCallback = ((NEVPNStatus)->Void)
    var tsChangedCallbacks:[TunnelStateChangedCallback] = []
    
    #if targetEnvironment(simulator)
    var _status:NEVPNStatus = .disconnected
    var status:NEVPNStatus {
        get { return _status }
        set {
            _status = newValue
            let zidStore = ZitiIdentityStore()
            let (zids, _)  = zidStore.loadAll()
            zids?.forEach { zid in
                if zid.isEnabled {
                    zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
                }
                _ = zidStore.update(zid, [.EdgeStatus])
            }
            tunnelStatusDidChange(Notification(name: NSNotification.Name.NEVPNStatusDidChange))
        }
    }
    #else
    var status:NEVPNStatus {
        get {
            if let status = tpm?.connection.status { return status }
            return .invalid
        }
    }
    #endif
    
    static let shared = TunnelMgr()
    private override init() {}
    deinit { NotificationCenter.default.removeObserver(self) }
    
    typealias LoadCompletionHandler = (NETunnelProviderManager?, Error?) -> Void
    func loadFromPreferences(_ bid:String, _ completionHandler: LoadCompletionHandler? = nil) {
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
                
                if let tmgr = self {
                    // Get notified when tunnel status changes
                    NotificationCenter.default.removeObserver(tmgr)
                    NotificationCenter.default.addObserver(tmgr, selector:
                        #selector(TunnelMgr.tunnelStatusDidChange(_:)), name:
                        NSNotification.Name.NEVPNStatusDidChange, object: nil)
                
                    tmgr.tpm = tpm
                    
                    // Get our logger config from provider
                    if let conf = (tpm.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration {
                        let pc = ProviderConfig()
                        if let error = pc.parseDictionary(conf) {
                            zLog.error("Unable to parse provider config to determine logger settings: \(error.localizedDescription)")
                        } else {
                            let ll = ZitiLog.LogLevel(rawValue: Int32(pc.logLevel)) ?? ZitiLog.LogLevel.INFO
                            zLog.info("Updating log level to \(pc.logLevel) (\(ll))")
                            ZitiLog.setLogLevel(ll)
                            
                            TunnelMgr.shared.tlsuvLoggingEnabled = Bool(pc.logTlsuv)
                            var tlsuvLl = ZitiLog.LogLevel.ERROR
                            if TunnelMgr.shared.tlsuvLoggingEnabled { tlsuvLl = ll }
                            ZitiLog.setLogLevel(tlsuvLl, module: "tlsuv")
                            Logger.updateRotateSettings(pc.logRotateDaily, pc.logRotateCount, pc.logRotateSizeMB)
                        }
                    } else {
                        zLog.info("No log level found.  Using default")
                    }
                    
                    completionHandler?(tpm, nil)
                    tmgr.tsChangedCallbacks.forEach { cb in cb(tmgr.status) }
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
                do {
                    try startTunnel()
                } catch {
                    zLog.error("Failed (re-)starting tunnel \(error.localizedDescription)")
                }
                
            }
            tsChangedCallbacks.forEach { cb in cb(.reasserting) }
        } else {
            tsChangedCallbacks.forEach { cb in cb(status) }
        }
    }
    
    func prefReloadHack(_ tpm: NETunnelProviderManager) {
        tpm.saveToPreferences { error in
            if let error = error {
                zLog.error(error.localizedDescription)
            } else {
                zLog.info("Saved successfully. Re-loading preferences")
                // ios hack per apple forums (else NEVPNErrorDomain Code=1 on starting tunnel)
                tpm.loadFromPreferences { [weak tpm] error in
                    zLog.error("Re-loaded preferences, error=\(error != nil). Attempting to start")
                    do {
                        zLog.info("Attempting to start tunnel after load from preferences")
                        try (tpm?.connection as? NETunnelProviderSession)?.startTunnel()
                    } catch {
                        zLog.error("Failed starting tunnel after re-enabling. \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func startTunnel() throws {
        guard let tpm = self.tpm else {
            zLog.error("Unable to access TPM")
            return
        }
        
        if tpm.isEnabled {
            guard let tps = (tpm.connection as? NETunnelProviderSession) else {
                zLog.error("Unable to access connection as NETunnelProviderSession")
                return
            }
            zLog.info("starting tunnel")
            try tps.startTunnel()
            zLog.info("start tunnel called with no error")
            
            if #available(iOS 16, *), #available(macOS 13, *) {
                tps.fetchLastDisconnectError { err in
                    guard let err = err else {
                        zLog.info("No lastDisconnect error found")
                        return
                    }
                    zLog.error("lastDisconnectError: \(err.localizedDescription)")
                    
                    zLog.info("Attempting reload prefs hack")
                    self.prefReloadHack(tpm)
                }
            }
        } else {
            zLog.warn("startTunnel - tunnel not enabled.  Re-enabling and starting tunnel")
            tpm.isEnabled = true
            self.prefReloadHack(tpm)
        }
    }
    
    func stopTunnel() {
        (tpm?.connection as? NETunnelProviderSession)?.stopTunnel()
    }
    
    func restartTunnel() {
        #if targetEnvironment(simulator)
        zLog.info("Simulator ignoring tunnel restart check")
        #else
        if self.status != .disconnected {
            zLog.info("Restarting tunnel")
            tunnelRestarting = true
            stopTunnel()
        }
        #endif
    }
    
    func loadZids() -> ZitiError? {
        let (loadedZids, err) = zidStore.loadAll()
        if err != nil || loadedZids == nil {
            zLog.warn(err?.errorDescription ?? "Error loading identities from store")
        }
        self.zids = loadedZids ?? []
        return err
    }
    
    func allEnabledZidsFullyAvailable() -> Bool {
        for z in zids {
            if z.isEnabled && (z.edgeStatus?.status ?? .Unavailable != .Available) {
                return false
            }
        }
        return true
    }
    
    func updateLogLevel(_ level:ZitiLog.LogLevel) {
        zLog.info("Updating log level to \(level)")
        ZitiLog.setLogLevel(level)
        var tlsuvLevel = ZitiLog.LogLevel.ERROR
        if self.tlsuvLoggingEnabled { tlsuvLevel = level }
        ZitiLog.setLogLevel(tlsuvLevel, module: "tlsuv")
        guard let tpm = tpm else {
            zLog.error("Invalid tunnel provider. Tunnel logging level not updated")
            return
        }
        
        if var conf = (tpm.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration {
            // update logLevel
            conf[ProviderConfig.LOG_LEVEL_KEY] = String(level.rawValue)
            conf[ProviderConfig.LOG_TLSUV_KEY] = self.tlsuvLoggingEnabled
            (tpm.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration = conf
            
            zLog.info("Updated providerConfiguration: \(conf)")
            
            tpm.saveToPreferences { error in
                if let error = error {
                    zLog.error(error.localizedDescription)
                } else {
                    // sendProviderMessage
                    zLog.info("Sending logLevel \(level) to provider")
                    let msg = IpcSetLogLevelMessage(level.rawValue)
                    self.ipcClient.sendToAppex(msg) { _, zErr in
                        guard zErr == nil else {
                            zLog.error("Unable to send provider message to update global logLevel to \(level): \(zErr!.localizedDescription)")
                            return
                        }
                    }
                    let tlsuvMsg = IpcSetLogLevelMessage(tlsuvLevel.rawValue, module: "tlsuv")
                    self.ipcClient.sendToAppex(tlsuvMsg) { _, zErr in
                        guard zErr == nil else {
                            zLog.error("Unable to send provider message to update tlsuv logLevel to \(level): \(zErr!.localizedDescription)")
                            return
                        }
                    }
                }
            }
        } else {
            zLog.info("No log level found.  Using default")
        }
    }
    
    func reassert() {
        guard self.status == .connected else {
            return
        }
        
        zLog.info("Notifying appex to reassert tunnel configuration")
        let msg = IpcReassertMessage()
        self.ipcClient.sendToAppex(msg) { _, zErr in
            guard zErr == nil else {
                zLog.error("Unable to send provider message to reassert tunnel configuration: \(zErr!.localizedDescription)")
                return
            }
        }
    }
    
    func sendEnabledMessage(_ zid:ZitiIdentity, _ completionHandler: @escaping (Int64) -> Void) {
        guard self.status == .connected else {
            completionHandler(0)
            return
        }
        
        let enabled = zid.isEnabled
        zLog.info("Sending message to set enabled to \(enabled) for identity \(zid.name):\(zid.id), controller: \(zid.czid?.ztAPI ?? "--")")
        let msg = IpcSetEnabledMessage(zid.id, enabled)
        self.ipcClient.sendToAppex(msg) { respMsg, zErr in
            guard zErr == nil else {
                zLog.error("Unable to send provider message to set enabled to \(enabled) for identity \(zid.name):\(zid.id), \(zErr!.localizedDescription)")
                return
            }
            guard let setEnabledRespMsg = respMsg as? IpcSetEnabledResponseMessage else {
                let msgType = respMsg != nil ? "\(respMsg!.meta.msgType)" : "unknown"
                zLog.error("Unexpected response message type \(msgType)")
                return
            }
            guard let code = setEnabledRespMsg.code else {
                zLog.error("Invalid code for IPC Set Enabled Response for \(zid.name):\(zid.id), controller: \(zid.czid?.ztAPI ?? "--")")
                return
            }
            completionHandler(code)
        }
    }
}
