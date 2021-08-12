/*
Copyright NetFoundry, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
import Foundation
import CZiti

enum IpcMessageType : Int32 {
    case Poll = 0
    case LogLevel
    case Dump
    case MfaEnroll
    case MfaEnrollResponse
    case MfaVerify
    case MfaVerifiyResponse
    case MfaRemove
    case MfaRemoveResponse
    case MfaAuthQuery
    case MfaAuthQueryResponse
    case MfaGetRecoveryCode
    case MfaNewRecoveryCode
    case MfaRecoveryCodesResponse
}

class IpcMessage : NSObject, Codable {
    var meta:IpcMessageMeta?
    var data:IpcMessageData?
}

class IpcMessageMeta : NSObject, Codable {
    //var type:IpcMessageType?
}

class IpcMessageData : NSObject, Codable {
}

class IpcLogLevelMessage : IpcMessageData {
    var logLevel:Int?
}

class IpcMfaEnrollMessage : IpcMessageData {
    
}

class IpcMfaEnrollmentResponse : IpcMessageData {
    var status:Int32?
    var mfaEnrollment:CZiti.ZitiMfaEnrollment?
}
