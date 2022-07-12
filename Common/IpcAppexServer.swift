//
// Copyright NetFoundry, Inc.
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

class IpcAppexServer : NSObject {
    let ptp:PacketTunnelProvider
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    
    typealias CompletionHandler = (Data?) -> Void
    public static let CONTEXT_EVENT_ENABLED_CALLBACK_KEY = "IpcAppexServer.ContextEventEnabledCallback"
    
    init(_ ptp:PacketTunnelProvider) {
        self.ptp = ptp
    }
    
    func errData(_ errStr:String) -> Data? {
        return try? encoder.encode(IpcErrorResponseMessage(errStr))
    }
    
    func processMessage(_ messageData:Data, completionHandler: CompletionHandler?) {
        guard let polyMsg = try? decoder.decode(IpcPolyMessage.self, from: messageData) else {
            let errStr = "Unable to decode IpcMessage"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        let baseMsg = polyMsg.msg
        zLog.debug("processing message of type \(baseMsg.meta.msgType)")
                
        switch baseMsg.meta.msgType {
        case .SetLogLevel: processSetLogLevel(baseMsg, completionHandler: completionHandler)
        case .UpdateLogRotateConfig: processUpdateLogRotateConfig(baseMsg, completionHandler: completionHandler)
        case .Reassert: processReassert(baseMsg, completionHandler: completionHandler)
        case .SetEnabled: processSetEnabled(baseMsg, completionHandler: completionHandler)
        case .DumpRequest: processDumpRequest(baseMsg, completionHandler: completionHandler)
        case .MfaEnrollRequest: processMfaEnrollRequest(baseMsg, completionHandler: completionHandler)
        case .MfaVerifyRequest: processMfaVerifyRequest(baseMsg, completionHandler: completionHandler)
        case .MfaRemoveRequest: processMfaRemoveRequest(baseMsg, completionHandler: completionHandler)
        case .MfaAuthQueryResponse: processMfaAuthQueryResponse(baseMsg, completionHandler: completionHandler)
        case .MfaGetRecoveryCodesRequest: processMfaGetRecoveryCodesRequest(baseMsg, completionHandler: completionHandler)
        case .MfaNewRecoveryCodesRequest: processMfaNewRecoveryCodesRequest(baseMsg, completionHandler: completionHandler)
        default:
            let errStr = "Unsupported IpcMessageType \(baseMsg.meta.msgType)"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
        }
    }
    
    func processSetLogLevel(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcSetLogLevelMessage, let logLevel = msg.logLevel else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }

        let lvl:ZitiLog.LogLevel = ZitiLog.LogLevel(rawValue: logLevel) ?? ZitiLog.LogLevel.INFO
        zLog.info("Updating LogLevel to \(lvl)")
        ZitiLog.setLogLevel(lvl)
        ptp.appLogLevel = lvl
        completionHandler?(nil)
    }
    
    func processUpdateLogRotateConfig(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        if let error = ptp.loadConfig() {
            zLog.error("Error loading tunnel config: \(error.localizedDescription)")
            return
        }
        Logger.updateRotateSettings(ptp.providerConfig.logRotateDaily, ptp.providerConfig.logRotateCount, ptp.providerConfig.logRotateSizeMB)
        completionHandler?(nil)
    }
    
    func processReassert(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        if let error = ptp.loadConfig() {
            zLog.error("Error loading tunnel config: \(error.localizedDescription)")
            // Don't return on error here - there are other reasons to reassert...
        }
        
        ptp.updateTunnelNetworkSettings { error in
            if let error = error {
                zLog.error("Error updating tunnel network settings: \(error.localizedDescription)")
            }
            completionHandler?(nil)
        }
    }
    
    func processSetEnabled(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcSetEnabledMessage, let enabled = msg.enabled else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }

        ziti.perform {
            zLog.info("Setting Enabled to \(enabled) for \(ziti.id.name ?? ""):\(ziti.id.id), controller: \(ziti.id.ztAPI)")
            
            if completionHandler != nil {
                ziti.userData[IpcAppexServer.CONTEXT_EVENT_ENABLED_CALLBACK_KEY] = completionHandler
            }
            ziti.setEnabled(enabled)
            
            // if all DNS is going thru the TUN, reset network settings (which fixes DNS issues on re-enable, flushing DNS cache I believe)
            if !self.ptp.providerConfig.interceptMatchedDns {
                self.ptp.updateTunnelNetworkSettings { error in
                    if let error = error {
                        zLog.error("Error updating tunnel network settings: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func processDumpRequest(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        let dumpStr = ptp.dumpZitis()
        zLog.info(dumpStr)
        
        guard let data = try? encoder.encode(IpcDumpResponseMessage(dumpStr)) else {
            let errStr = "Unable to encode IpcDumpResponseMessage"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        completionHandler?(data)
    }
    
    func processMfaEnrollRequest(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcMfaEnrollRequestMessage else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        ziti.mfaEnroll { _, status, mfaEnrollment in
            let respMsg = IpcMfaEnrollResponseMessage(status, mfaEnrollment: mfaEnrollment)
            guard let data = try? self.encoder.encode(respMsg) else {
                let errStr = "Unable to encode response message"
                zLog.error(errStr)
                completionHandler?(self.errData(errStr))
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaVerifyRequest(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcMfaVerifyRequestMessage else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let code = msg.code else {
            let errStr = "Invalid (nil) code"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        ziti.mfaVerify(code) { _, status in
            let respMsg = IpcMfaStatusResponseMessage(status)
            guard let data = try? self.encoder.encode(respMsg) else {
                let errStr = "Unable to encode response message"
                zLog.error(errStr)
                completionHandler?(self.errData(errStr))
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaRemoveRequest(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcMfaRemoveRequestMessage else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let code = msg.code else {
            let errStr = "Invalid (nil) code"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        ziti.mfaRemove(code) { _, status in
            let respMsg = IpcMfaStatusResponseMessage(status)
            guard let data = try? self.encoder.encode(respMsg) else {
                let errStr = "Unable to encode response message"
                zLog.error(errStr)
                completionHandler?(self.errData(errStr))
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaAuthQueryResponse(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcMfaAuthQueryResponseMessage else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let code = msg.code else {
            let errStr = "Invalid (nil) code"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        ziti.mfaAuth(code) { _, status in
            let respMsg = IpcMfaStatusResponseMessage(status)
            guard let data = try? self.encoder.encode(respMsg) else {
                let errStr = "Unable to encode response message"
                zLog.error(errStr)
                completionHandler?(self.errData(errStr))
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaGetRecoveryCodesRequest(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcMfaGetRecoveryCodesRequestMessage else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let code = msg.code else {
            let errStr = "Invalid (nil) code"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        ziti.mfaGetRecoveryCodes(code) { _, status, codes in
            let respMsg = IpcMfaRecoveryCodesResponseMessage(status, codes)
            guard let data = try? self.encoder.encode(respMsg) else {
                let errStr = "Unable to encode response message"
                zLog.error(errStr)
                completionHandler?(self.errData(errStr))
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaNewRecoveryCodesRequest(_ baseMsg:IpcMessage, completionHandler: CompletionHandler?) {
        guard let msg = baseMsg as? IpcMfaNewRecoveryCodesRequestMessage else {
            let errStr = "Unexpected message type"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.zitiTunnelDelegate?.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            let errStr = "Unable to find connected identity for id \(msg.meta.zid ?? "nil")"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let code = msg.code else {
            let errStr = "Invalid (nil) code"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        
        ziti.mfaNewRecoveryCodes(code) { _, status, codes in
            let respMsg = IpcMfaRecoveryCodesResponseMessage(status, codes)
            guard let data = try? self.encoder.encode(respMsg) else {
                let errStr = "Unable to encode response message"
                zLog.error(errStr)
                completionHandler?(self.errData(errStr))
                return
            }
            completionHandler?(data)
        }
    }
}

