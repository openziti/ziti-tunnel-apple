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
                var respMsg:IpcMessage? = nil
                var zErr:ZitiError? = nil
                
                if let data = respData {
                    if let errMsg = try? self.decoder.decode(IpcErrorResponseMessage.self, from: data), errMsg.meta.msgType == .ErrorResponse {
                        let errorDescription = errMsg.errorDescription ?? "\(errMsg.errorCode)"
                        zLog.error("Error message received from IPC server: \"\(errorDescription)\"")
                        zErr = ZitiError(errorDescription, errorCode: errMsg.errorCode)
                    } else if let respType = msg.meta.respType {
                        guard let rMsg = try? self.decoder.decode(respType, from: data) else {
                            let errStr = "Unable to decode response message for message type \(msg.meta.msgType)"
                            zLog.error(errStr)
                            cb?(nil, ZitiError(errStr))
                            return
                        }
                        respMsg = rMsg
                    } else {
                        // We don't know the type at this point. May need to come up with something better...
                        guard let rMsg = try? self.decoder.decode(IpcMessage.self, from: data) else {
                            let errStr = "Unable to decode response message for \(msg.meta.msgType) message"
                            zLog.error(errStr)
                            cb?(nil, ZitiError(errStr))
                            return
                        }
                        respMsg = rMsg
                    }
                }
                cb?(respMsg, zErr)
            }
        } catch {
            let errStr = "Unable to send provider message type \(msg.meta.msgType): \(error)"
            zLog.error(errStr)
            cb?(nil, ZitiError(errStr))
        }
    }
    
    func sendPollMsg() {
        sendToAppex(IpcPollMessage()) { respMsg, zErr in
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
    func startPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.sendPollMsg()
            if self?.pollTimer == nil {
                self?.pollTimer = Timer.scheduledTimer(withTimeInterval: self?.pollInterval ?? 0.0, repeats: true) { _ in
                    self?.sendPollMsg()
                }
            }
        }
    }
    
    func stopPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
        }
    }
}

extension Notification.Name {
    static let onZitiPollResponse = Notification.Name("on-ziti-poll-response")
}
