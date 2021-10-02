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
        pruneMsgQueue()
        queue.append(msg)
        qLock.unlock()
    }
    
    func pruneMsgQueue() {
        queue = queue.filter {
            let age = -($0.meta.createdAt.timeIntervalSinceNow)
            return age < TimeInterval(60.0)
        }
    }
    
    func errData(_ errStr:String) -> Data? {
        return try? encoder.encode(IpcErrorResponseMessage(errStr))
    }
    
    func processMessage(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let ipcMsg = try? decoder.decode(IpcMessage.self, from: messageData) else {
            let errStr = "Unable to decode IpcMessage"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
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
            let errStr = "Unsupported IpcMessageType \(ipcMsg.meta.msgType)"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
        }
    }
    
    func processPoll(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        var msg:IpcMessage?
        
        qLock.lock()
        pruneMsgQueue()
        if queue.count > 0 {
            msg = queue.removeFirst()
        }
        qLock.unlock()
        
        if let msg = msg {
            guard let data = try? encoder.encode(msg) else {
                let errStr = "Unable to encode popped IpcMessage of type \(msg.meta.msgType)"
                zLog.error(errStr)
                completionHandler?(errData(errStr))
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
            let errStr = "Unable to decode .SetLogLevel message"
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
    
    func processDumpRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
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
    
    func processMfaEnrollRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaEnrollRequestMessage.self, from: messageData) else {
            let errStr = "Unable to decode message"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
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
    
    func processMfaVerifyRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaVerifyRequestMessage.self, from: messageData) else {
            let errStr = "Unable to decode message"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
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
    
    func processMfaRemoveRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaRemoveRequestMessage.self, from: messageData) else {
            let errStr = "Unable to decode message"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
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
    
    func processMfaAuthQueryResponse(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaAuthQueryResponseMessage.self, from: messageData) else {
            let errStr = "Unable to decode message"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
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
    
    func processMfaGetRecoveryCodesRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaGetRecoveryCodesRequestMessage.self, from: messageData) else {
            let errStr = "Unable to decode message"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
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
    
    func processMfaNewRecoveryCodesRequest(_ messageData:Data, completionHandler: ((Data?) -> Void)?) {
        guard let msg = try? decoder.decode(IpcMfaNewRecoveryCodesRequestMessage.self, from: messageData) else {
            let errStr = "Unable to decode message"
            zLog.error(errStr)
            completionHandler?(errData(errStr))
            return
        }
        guard let ziti = ptp.allZitis.first(where: { $0.id.id == msg.meta.zid }) else {
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

