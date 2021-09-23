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
    
    var queue:[IpcMessage] = []
    var qLock = NSLock()
    
    init(_ ptp:PacketTunnelProvider) {
        self.ptp = ptp
    }
    
    func queueMsg(_ msg:IpcMessage) {
        qLock.lock()
        queue.append(msg) // TODO: need to time out messages since the app might not be running all the time...
        qLock.unlock()
    }
    
    func processMessage(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let ipcMsg = try? decoder.decode(IpcMessage.self, from: messageData) else {
            zLog.error("Unable to decode IpcMessage")
            completionHandler?(nil)
            return
        }
        zLog.debug("processing message of type \(ipcMsg.meta.msgType)")
        
        switch ipcMsg.meta.msgType {
        case .Poll: processPoll(messageData, completionHandler: completionHandler)
        case .SetLogLevel: processSetLogLevel(messageData, completionHandler: completionHandler)
        case .DumpRequest: processDumpRequest(messageData, completionHandler: completionHandler)
        case .MfaEnrollRequest: processMfaEnrollRequest(messageData, completionHandler: completionHandler)
        case .MfaVerifyRequest: processMfaVerifyRequest(messageData, completionHandler: completionHandler)
        case .MfaRemoveRequest: processMfaRemoveRequest(messageData, completionHandler: completionHandler)
        case .MfaAuthQueryResponse: processMfaAuthQueryResponse(messageData, completionHandler: completionHandler)
        case .MfaGetRecoveryCodesRequest: processMfaGetRecoveryCodesRequest(messageData, completionHandler: completionHandler)
        case .MfaNewRecoveryCodesRequest: processMfaNewRecoveryCodesRequest(messageData, completionHandler: completionHandler)
        default:
            zLog.error("Unsupported IpcMessageType \(ipcMsg.meta.msgType)")
            completionHandler?(nil)
        }
    }
    
    func processPoll(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        var msg:IpcMessage?
        
        qLock.lock()
        if queue.count > 0 {
            msg = queue.removeFirst() // TODO: need to time out messages since the app might not be running all the time...
        }
        qLock.unlock()
        
        if let msg = msg {
            guard let data = try? encoder.encode(msg) else {
                zLog.error("Unable to encode popped IpcMessage of type \(msg.meta.msgType)")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        } else {
            completionHandler?(nil)
        }
    }
    
    func processSetLogLevel(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcSetLogLevelMessage.self, from: messageData),
              let logLevel = msg.logLevel else {
            zLog.error("Unable to decode .SetLogLevel message")
            return
        }

        let lvl:ZitiLog.LogLevel = ZitiLog.LogLevel(rawValue: logLevel) ?? ZitiLog.LogLevel.INFO
        zLog.info("Updating LogLevel to \(lvl)")
        ZitiLog.setLogLevel(lvl)
        ptp.appLogLevel = lvl
        completionHandler?(nil)
    }
    
    func processDumpRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        let dumpStr = ptp.dumpZitis()
        zLog.info(dumpStr)
        
        guard let data = try? encoder.encode(IpcDumpResponseMessage(dumpStr)) else {
            zLog.error("Unable to encode IpcDumpResponseMessage")
            completionHandler?(nil)
            return
        }
        completionHandler?(data)
    }
    
    func processMfaEnrollRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaEnrollRequestMessage.self, from: messageData) else {
            zLog.error("Unable to decode message")
            completionHandler?(nil)
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            zLog.error("Unable to lookup identity with id = \(msg.meta.zid ?? "nil")")
            completionHandler?(nil)
            return
        }
        
        ziti.mfaEnroll { _, status, mfaEnrollment in
            let respMsg = IpcMfaEnrollResponseMessage(status, mfaEnrollment: mfaEnrollment)
            guard let data = try? self.encoder.encode(respMsg) else {
                zLog.error("Unable to encode response message")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaVerifyRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaVerifyRequestMessage.self, from: messageData) else {
            zLog.error("Unable to decode message")
            completionHandler?(nil)
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            zLog.error("Unable to lookup identity with id = \(msg.meta.zid ?? "nil")")
            completionHandler?(nil)
            return
        }
        guard let code = msg.code else {
            zLog.error("Invalid (nil) code")
            completionHandler?(nil)
            return
        }
        
        ziti.mfaVerify(code) { _, status in
            let respMsg = IpcMfaStatusResponseMessage(status)
            guard let data = try? self.encoder.encode(respMsg) else {
                zLog.error("Unable to encode response message")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaRemoveRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaRemoveRequestMessage.self, from: messageData) else {
            zLog.error("Unable to decode message")
            completionHandler?(nil)
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            zLog.error("Unable to lookup identity with id = \(msg.meta.zid ?? "nil")")
            completionHandler?(nil)
            return
        }
        guard let code = msg.code else {
            zLog.error("Invalid (nil) code")
            completionHandler?(nil)
            return
        }
        
        ziti.mfaRemove(code) { _, status in
            let respMsg = IpcMfaStatusResponseMessage(status)
            guard let data = try? self.encoder.encode(respMsg) else {
                zLog.error("Unable to encode response message")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaAuthQueryResponse(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaAuthQueryResponseMessage.self, from: messageData) else {
            zLog.error("Unable to decode message")
            completionHandler?(nil)
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            zLog.error("Unable to lookup identity with id = \(msg.meta.zid ?? "nil")")
            completionHandler?(nil)
            return
        }
        guard let code = msg.code else {
            zLog.error("Invalid (nil) code")
            completionHandler?(nil)
            return
        }
        
        ziti.mfaAuth(code) { _, status in
            let respMsg = IpcMfaStatusResponseMessage(status)
            guard let data = try? self.encoder.encode(respMsg) else {
                zLog.error("Unable to encode response message")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaGetRecoveryCodesRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaGetRecoveryCodesRequestMessage.self, from: messageData) else {
            zLog.error("Unable to decode message")
            completionHandler?(nil)
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            zLog.error("Unable to lookup identity with id = \(msg.meta.zid ?? "nil")")
            completionHandler?(nil)
            return
        }
        guard let code = msg.code else {
            zLog.error("Invalid (nil) code")
            completionHandler?(nil)
            return
        }
        
        ziti.mfaGetRecoveryCodes(code) { _, status, codes in
            let respMsg = IpcMfaRecoveryCodesResponseMessage(status, codes)
            guard let data = try? self.encoder.encode(respMsg) else {
                zLog.error("Unable to encode response message")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        }
    }
    
    func processMfaNewRecoveryCodesRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaNewRecoveryCodesRequestMessage.self, from: messageData) else {
            zLog.error("Unable to decode message")
            completionHandler?(nil)
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
            zLog.error("Unable to lookup identity with id = \(msg.meta.zid ?? "nil")")
            completionHandler?(nil)
            return
        }
        guard let code = msg.code else {
            zLog.error("Invalid (nil) code")
            completionHandler?(nil)
            return
        }
        
        ziti.mfaNewRecoveryCodes(code) { _, status, codes in
            let respMsg = IpcMfaRecoveryCodesResponseMessage(status, codes)
            guard let data = try? self.encoder.encode(respMsg) else {
                zLog.error("Unable to encode response message")
                completionHandler?(nil)
                return
            }
            completionHandler?(data)
        }
    }
}

