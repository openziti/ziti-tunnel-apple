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

typealias IpcResponseCallback = (_ msg:IpcMessage?, _ error:ZitiError?) -> Void

class IpcAppClient : NSObject {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    var pollInterval = TimeInterval(5.0)
    var pollTimer:Timer?
    
    func sendToAppex(_ msg:IpcMessage, _ cb:IpcResponseCallback?) {
        guard let conn = (TunnelMgr.shared.tpm?.connection as? NETunnelProviderSession) else {
            let errStr = "Invalid tunnel provider"
            zLog.error(errStr)
            cb?(nil, ZitiError(errStr))
            return
        }
        
        do {
            let data = try encoder.encode(msg)
            if let dbgStr = String(data:data, encoding: .utf8) {
                zLog.debug("\(msg.meta.msgType): \(dbgStr)")
            }
            
            try conn.sendProviderMessage(data) { respData in
                if msg.meta.respType == nil && respData != nil {
                    zLog.warn("Unexpected IPC response received for message type \(msg.meta.msgType)")
                }
                var respMsg:IpcMessage? = nil
                if let respType = msg.meta.respType, let data = respData {
                    guard let msg = try? self.decoder.decode(respType, from: data) else {
                        let errStr = "Unable to decode response message for message type \(msg.meta.msgType)"
                        zLog.error(errStr)
                        cb?(nil, ZitiError(errStr))
                        return
                    }
                    respMsg = msg
                }
                cb?(respMsg, nil)
            }
        } catch {
            let errStr = "Unable to send provider message type \(msg.meta.msgType): \(error)"
            zLog.error(errStr)
            cb?(nil, ZitiError(errStr))
        }
    }
    
    func startPolling() {
        DispatchQueue.main.async { [weak self] in
            if self?.pollTimer != nil { self?.pollTimer?.invalidate() }
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: self?.pollInterval ?? 0.0, repeats: true) { _ in
                self?.sendToAppex(IpcPollMessage()) { respMsg, zErr in
                    guard zErr == nil else {
                        zLog.error(zErr!.localizedDescription)
                        return
                    }
                    guard let respMsg = respMsg else { // perfectly legit
                        return
                    }
                    
                    zLog.info("IpcMessage received of type \(respMsg.meta.msgType)")
                    NotificationCenter.default.post(name: .onZitiPollResponse, object: self, userInfo: ["ipcMessage":respMsg])
                }
            }
        }
    }
    
    func stopPolling() {
        DispatchQueue.main.async { [weak self] in
            if self?.pollTimer != nil { self?.pollTimer?.invalidate() }
        }
    }
}

extension Notification.Name {
    static let onZitiPollResponse = Notification.Name("on-ziti-poll-response")
}
