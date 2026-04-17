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

import XCTest
@testable import Ziti_Desktop_Edge

class IpcMessagesTests: XCTestCase {

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    // MARK: - IpcAppexNotificationMessage

    func testAppexNotification_roundTrip() throws {
        let msg = IpcAppexNotificationMessage("zid-1", "mfa", "MFA Required", "Identity X", "Please verify", ["Verify", "Dismiss"])
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcAppexNotificationMessage)
        let notification = decoded.msg as! IpcAppexNotificationMessage
        XCTAssertEqual(notification.meta.zid, "zid-1")
        XCTAssertEqual(notification.meta.msgType, .AppexNotification)
        XCTAssertEqual(notification.category, "mfa")
        XCTAssertEqual(notification.title, "MFA Required")
        XCTAssertEqual(notification.subtitle, "Identity X")
        XCTAssertEqual(notification.body, "Please verify")
        XCTAssertEqual(notification.actions, ["Verify", "Dismiss"])
    }

    // MARK: - IpcAppexNotificationActionMessage

    func testAppexNotificationAction_roundTrip() throws {
        let msg = IpcAppexNotificationActionMessage("zid-1", "mfa", "Verify")
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcAppexNotificationActionMessage)
        let action = decoded.msg as! IpcAppexNotificationActionMessage
        XCTAssertEqual(action.category, "mfa")
        XCTAssertEqual(action.action, "Verify")
    }

    // MARK: - IpcErrorResponseMessage

    func testErrorResponse_roundTrip() throws {
        let msg = IpcErrorResponseMessage("something went wrong", 42)
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcErrorResponseMessage)
        let error = decoded.msg as! IpcErrorResponseMessage
        XCTAssertEqual(error.errorDescription, "something went wrong")
        XCTAssertEqual(error.errorCode, 42)
    }

    // MARK: - IpcSetLogLevelMessage

    func testSetLogLevel_roundTrip() throws {
        let msg = IpcSetLogLevelMessage(3, module: "tunnel")
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcSetLogLevelMessage)
        let logMsg = decoded.msg as! IpcSetLogLevelMessage
        XCTAssertEqual(logMsg.logLevel, 3)
        XCTAssertEqual(logMsg.module, "tunnel")
    }

    // MARK: - IpcSetEnabledMessage

    func testSetEnabled_roundTrip() throws {
        let msg = IpcSetEnabledMessage("zid-1", true)
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcSetEnabledMessage)
        let enabled = decoded.msg as! IpcSetEnabledMessage
        XCTAssertEqual(enabled.meta.zid, "zid-1")
        XCTAssertEqual(enabled.enabled, true)
    }

    // MARK: - IpcSetEnabledResponseMessage

    func testSetEnabledResponse_roundTrip() throws {
        let msg = IpcSetEnabledResponseMessage("zid-1", 0)
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcSetEnabledResponseMessage)
        let resp = decoded.msg as! IpcSetEnabledResponseMessage
        XCTAssertEqual(resp.code, 0)
    }

    // MARK: - IpcDumpResponseMessage

    func testDumpResponse_roundTrip() throws {
        let msg = IpcDumpResponseMessage("debug dump output here")
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcDumpResponseMessage)
        let dump = decoded.msg as! IpcDumpResponseMessage
        XCTAssertEqual(dump.dump, "debug dump output here")
    }

    // MARK: - IpcMfaVerifyRequestMessage

    func testMfaVerifyRequest_roundTrip() throws {
        let msg = IpcMfaVerifyRequestMessage("zid-1", "123456")
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcMfaVerifyRequestMessage)
        let verify = decoded.msg as! IpcMfaVerifyRequestMessage
        XCTAssertEqual(verify.meta.zid, "zid-1")
        XCTAssertEqual(verify.code, "123456")
    }

    // MARK: - IpcMfaRecoveryCodesResponseMessage

    func testMfaRecoveryCodesResponse_roundTrip() throws {
        let msg = IpcMfaRecoveryCodesResponseMessage(0, ["code1", "code2", "code3"])
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcMfaRecoveryCodesResponseMessage)
        let codes = decoded.msg as! IpcMfaRecoveryCodesResponseMessage
        XCTAssertEqual(codes.status, 0)
        XCTAssertEqual(codes.codes, ["code1", "code2", "code3"])
    }

    // MARK: - IpcExternalAuthRequestMessage

    func testExternalAuthRequest_roundTrip() throws {
        let msg = IpcExternalAuthRequestMessage("zid-1", "google")
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)

        XCTAssertTrue(decoded.msg is IpcExternalAuthRequestMessage)
        let auth = decoded.msg as! IpcExternalAuthRequestMessage
        XCTAssertEqual(auth.meta.zid, "zid-1")
        XCTAssertEqual(auth.provider, "google")
    }

    // MARK: - Simple messages (no extra fields)

    func testReassertMessage_roundTrip() throws {
        let msg = IpcReassertMessage()
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)
        XCTAssertEqual(decoded.msg.meta.msgType, .Reassert)
    }

    func testDumpRequestMessage_roundTrip() throws {
        let msg = IpcDumpRequestMessage()
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)
        XCTAssertEqual(decoded.msg.meta.msgType, .DumpRequest)
    }

    func testUpdateLogRotateConfig_roundTrip() throws {
        let msg = IpcUpdateLogRotateConfigMessage()
        let poly = IpcPolyMessage(msg)
        let data = try encoder.encode(poly)
        let decoded = try decoder.decode(IpcPolyMessage.self, from: data)
        XCTAssertEqual(decoded.msg.meta.msgType, .UpdateLogRotateConfig)
    }

    // MARK: - IpcMessageType mapping

    func testMessageType_mapsToCorrectClass() {
        XCTAssertTrue(IpcMessageType.AppexNotification.type == IpcAppexNotificationMessage.self)
        XCTAssertTrue(IpcMessageType.ErrorResponse.type == IpcErrorResponseMessage.self)
        XCTAssertTrue(IpcMessageType.SetLogLevel.type == IpcSetLogLevelMessage.self)
        XCTAssertTrue(IpcMessageType.SetEnabled.type == IpcSetEnabledMessage.self)
        XCTAssertTrue(IpcMessageType.SetEnabledResponse.type == IpcSetEnabledResponseMessage.self)
        XCTAssertTrue(IpcMessageType.DumpRequest.type == IpcDumpRequestMessage.self)
        XCTAssertTrue(IpcMessageType.DumpResponse.type == IpcDumpResponseMessage.self)
        XCTAssertTrue(IpcMessageType.Reassert.type == IpcReassertMessage.self)
    }

    // MARK: - Meta preserves msgId across encode/decode

    func testMeta_preservesMsgId() throws {
        let msg = IpcReassertMessage()
        let originalId = msg.meta.msgId
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(IpcMessage.self, from: data)
        XCTAssertEqual(decoded.meta.msgId, originalId)
    }
}
