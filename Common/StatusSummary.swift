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

/// App-side state for support (version, tunnel, settings source, identities), shown ahead of the tunnel's snapshot
class StatusSummary {
    static func statusDescription(_ status:NEVPNStatus) -> String {
        switch status {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reasserting: return "Reasserting"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown (\(status.rawValue))"
        }
    }

    // Saved settings come back as NSNumber, so booleans would otherwise show as 1 or 0
    private static func valueDescription(_ value:Any) -> String {
        if let num = value as? NSNumber, ProviderConfig.isBoolean(num) {
            return num.boolValue ? "true" : "false"
        }
        return "\(value)"
    }

    /// `config` is the saved tunnel configuration, listed as stored (invalid values included)
    static func text(version:String, status:NEVPNStatus, config:ProviderConfigDict?, zids:[ZitiIdentity]) -> String {
        var lines = [
            "======= Status ==========",
            version,
            "Tunnel: \(statusDescription(status))"]
        if let config = config {
            lines.append("Tunnel settings: \(ProviderConfig.isLocked(config) ? "Locked by an installed profile" : "Editable")")
            lines += config.keys.sorted().map { "  \($0): \(valueDescription(config[$0]!))" }
        } else {
            lines.append("Tunnel settings: None saved")
        }
        lines.append("Identities: \(zids.count)")
        for zid in zids {
            lines.append("")
            lines.append("Identity: \(zid.name) [\(zid.id)]")
            lines.append("  Controllers: \((zid.czid?.ztAPIs ?? []).joined(separator: ", "))")
            lines.append("  Controller version: \(zid.controllerVersion ?? "--")")
            lines.append("  Enrollment: \(zid.enrollmentStatusDisplay)")
            lines.append("  Enabled: \(zid.isEnabled)")
            lines.append("  Edge: \(zid.edgeStatus?.status.rawValue ?? "--")")
            if zid.isMfaEnabled {
                lines.append("  MFA: \(zid.isMfaVerified ? "Verified" : "Not verified")\(zid.isMfaPending ? ", pending" : "")")
            }
            lines.append("  Services: \(zid.services.count)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Whether the tunnel provider is running and can return its snapshot, e.g., while still connecting
    static func canDump(_ status:NEVPNStatus) -> Bool {
        return status == .connecting || status == .connected || status == .reasserting
    }

    /// Calls back on the main queue with the summary, followed by the tunnel's snapshot when it's running
    static func snapshot(_ completion:@escaping (String) -> Void) {
        let tunnelMgr = TunnelMgr.shared
        let config = (tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        let summary = text(version: Version.verboseStr, status: tunnelMgr.status, config: config, zids: tunnelMgr.zids)
        guard canDump(tunnelMgr.status) else {
            DispatchQueue.main.async { completion(summary + "\nNo connection data available\n") }
            return
        }
        tunnelMgr.ipcClient.sendToAppex(IpcDumpRequestMessage()) { respMsg, zErr in
            var dump = "No connection data available\n"
            if let zErr = zErr {
                zLog.error("Unable to send provider message for snapshot (dump): \(zErr.localizedDescription)")
            } else if let str = (respMsg as? IpcDumpResponseMessage)?.dump {
                zLog.info(str)
                if !str.isEmpty { dump = str }
            } else {
                zLog.error("Unable to parse snapshot (dump) string from response message")
            }
            DispatchQueue.main.async { completion(summary + "\n" + dump) }
        }
    }
}
