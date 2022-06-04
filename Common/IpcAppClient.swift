//
// Copyright NetFoundry Inc.
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

class IpcAppClient : NSObject, ZitiIdentityStoreDelegate {
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let zidStore = ZitiIdentityStore()
    
    override init() {
        super.init()
        zidStore.delegate = self
        _ = zidStore.loadAll()
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .onNewOrChangedId, object: self, userInfo: ["zid":zid])
            
            // appexNotifications
            zid.appexNotifications?.forEach { polyMsg in
                // filter out old notification IpcMessages since app won't always be running
                let now = Date().timeIntervalSince1970
                let msgTime = polyMsg.msg.meta.createdAt.timeIntervalSince1970
                if (now - msgTime) < TimeInterval(5.0) {
                    NotificationCenter.default.post(name: .onAppexNotification, object: self, userInfo: ["ipcMessage":polyMsg.msg])
                } else {
                    zLog.warn("Discarding stale message of type \(polyMsg.msg.meta.msgType)")
                }
            }
            if zid.appexNotifications != nil {
                zid.appexNotifications = nil
                _ = self.zidStore.store(zid)
            }
        }
    }
    
    func onRemovedId(_ idString: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .onRemovedId, object: self, userInfo: ["id":idString])
        }
    }
    
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
}

extension Notification.Name {
    static let onAppexNotification = Notification.Name("on-appex-notification")
    static let onNewOrChangedId = Notification.Name("on-new-or-changed-id")
    static let onRemovedId = Notification.Name("on-removed-id")
}
