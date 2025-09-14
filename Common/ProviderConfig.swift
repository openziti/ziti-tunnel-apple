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

enum ProviderConfigError : Error {
    case invalidIpAddress
    case invalidSubnetMask
    case invalidMtu
    case invalidDnsAddresses
    case invalidFallbackDns
    case invalidLogRotateCount
    case invalidLogRotateSizeMB

    var description: String {
        switch self {
        case .invalidIpAddress: return "Invalid IP Address (expect valid IPv4 address)"
        case .invalidSubnetMask: return "Invalid Subnet Mask (axpect valid IPv4 subnet mask)"
        case .invalidMtu: return "Invalid MTU"
        case .invalidDnsAddresses: return "Invalid DNS Addresses (expect comma-delimited list of IPv4 addresses)"
        case .invalidFallbackDns: return "Invalid Fallback DNS (expect valid IPv4 address)"
        case .invalidLogRotateCount: return "Invalid log rotation count"
        case .invalidLogRotateSizeMB: return "Invalid log rotation size (MB)"
        }
    }
}

typealias ProviderConfigDict = [String : Any]

class ProviderConfig : NSObject {
    
    static var IP_KEY = "ip"
    static var SUBNET_KEY = "subnet"
    static var MTU_KEY = "mtu"
    static var DNS_KEY = "dns"
    static var FALLBACK_DNS_ENABLED_KEY = "fallbackDnsEnabled"
    static var FALLBACK_DNS_KEY = "fallbackDns"
    static var INTERCEPT_MATCHED_DNS_KEY = "interceptMatchedDns"
    static var LOG_LEVEL_KEY = "logLevel"
    static var LOG_TLSUV_KEY = "logTlsuv"
    static var LOW_POWER_MODE_KEY = "lowPowerMode"
    static var LOG_ROTATE_DAILY_KEY = "logRotateDaily"
    static var LOG_ROTATE_COUNT_KEY = "logRotateCount"
    static var LOG_ROTATE_SIZEMB_KEY = "logRotateSizeMB"
    
    // some defaults in case .mobileconfig not used
    var ipAddress:String = "100.64.0.1"
    var subnetMask:String = "255.192.0.0"
#if os(macOS)
    var mtu:Int = 4000
#else
    var mtu:Int = 4000
#endif
    var dnsAddresses:[String] = ["100.64.0.2"]
    var fallbackDnsEnabled = false
    var fallbackDns:String = "1.1.1.1"
    var username = "Ziti"
#if os(macOS)
    var localizedDescription = "Ziti Desktop Edge"
#else
    var localizedDescription = "Ziti Mobile Edge"
#endif
    var logLevel:Int = Int(ZitiLog.LogLevel.INFO.rawValue)
    var logTlsuv:Bool = false
    var interceptMatchedDns:Bool = true
    
    // If never stored, set default value to false
#if os(macOS)
    var lowPowerMode:Bool = false
#else
    var lowPowerMode:Bool = false
#endif
    
#if os(macOS)
    var logRotateDaily:Bool = true
    var logRotateCount:Int = 5
    var logRotateSizeMB:Int = 50
#else
    var logRotateDaily:Bool = true
    var logRotateCount:Int = 2
    var logRotateSizeMB:Int = 5
#endif
    
    func createDictionary() -> ProviderConfigDict {
        return [ProviderConfig.IP_KEY: self.ipAddress,
                ProviderConfig.SUBNET_KEY: self.subnetMask,
                ProviderConfig.MTU_KEY: String(self.mtu),
                ProviderConfig.LOG_LEVEL_KEY: String(self.logLevel),
                ProviderConfig.LOG_TLSUV_KEY: Bool(self.logTlsuv),
                ProviderConfig.DNS_KEY: self.dnsAddresses.joined(separator: ","),
                ProviderConfig.FALLBACK_DNS_ENABLED_KEY: self.fallbackDnsEnabled,
                ProviderConfig.FALLBACK_DNS_KEY: self.fallbackDns,
                ProviderConfig.LOW_POWER_MODE_KEY: self.lowPowerMode,
                ProviderConfig.INTERCEPT_MATCHED_DNS_KEY: self.interceptMatchedDns,
                ProviderConfig.LOG_ROTATE_DAILY_KEY: self.logRotateDaily,
                ProviderConfig.LOG_ROTATE_COUNT_KEY: String(self.logRotateCount),
                ProviderConfig.LOG_ROTATE_SIZEMB_KEY: String(self.logRotateSizeMB)]
    }
    
    private func isValidIpAddress(_ obj:Any?) -> Bool {
        guard let str = obj as? String else { return false }
        return IPUtils.isValidIpV4Address(str)
    }
    
    func validateDictionaty(_ conf:ProviderConfigDict) -> ProviderConfigError? {
        if !isValidIpAddress(conf[ProviderConfig.IP_KEY]) {
            return ProviderConfigError.invalidIpAddress
        }
        if !isValidIpAddress(conf[ProviderConfig.SUBNET_KEY]) {
            return ProviderConfigError.invalidSubnetMask
        }
        if let dns = conf[ProviderConfig.DNS_KEY] as? String {
            let dnsArray = dns.components(separatedBy: ",")
            if dnsArray.count == 0 || dnsArray.contains(where: { !isValidIpAddress($0) }) {
                return ProviderConfigError.invalidDnsAddresses
            }
        } else {
            return ProviderConfigError.invalidDnsAddresses
        }
        
        let fallbackEnabled = conf[ProviderConfig.FALLBACK_DNS_ENABLED_KEY] as? Bool ?? false
        if fallbackEnabled && !isValidIpAddress(conf[ProviderConfig.FALLBACK_DNS_KEY]) {
            return ProviderConfigError.invalidFallbackDns
        }
        guard let mtuStr = conf[ProviderConfig.MTU_KEY] as? String, let _ = Int(mtuStr) else {
            return ProviderConfigError.invalidMtu
        }
        
        if let lrCount = conf[ProviderConfig.LOG_ROTATE_COUNT_KEY] as? String {
            guard let _ = Int(lrCount) else {
                return ProviderConfigError.invalidLogRotateCount
            }
        }
        
        if let lrSize = conf[ProviderConfig.LOG_ROTATE_SIZEMB_KEY] as? String {
            guard let _ = Int(lrSize) else {
                return ProviderConfigError.invalidLogRotateSizeMB
            }
        }
        return nil
    }
    
    func parseDictionary(_ conf:ProviderConfigDict) -> ProviderConfigError? {
        if let error = validateDictionaty(conf) { return error }
        if let ipAddress = conf[ProviderConfig.IP_KEY] as? String {
            self.ipAddress = ipAddress.trimmingCharacters(in: .whitespaces)
        }
        if let subnetMask = conf[ProviderConfig.SUBNET_KEY] as? String {
            self.subnetMask = subnetMask.trimmingCharacters(in: .whitespaces)
        }
        if let mtu = conf[ProviderConfig.MTU_KEY] as? String, let mtuInt = Int(mtu) {
            self.mtu = mtuInt
        }
        if let dnsAddresses = conf[ProviderConfig.DNS_KEY] as? String {
            self.dnsAddresses = dnsAddresses.trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
        }
        if let fallbackDns = conf[ProviderConfig.FALLBACK_DNS_KEY] as? String {
            self.fallbackDns = fallbackDns.trimmingCharacters(in: .whitespaces)
        }
        self.fallbackDnsEnabled = conf[ProviderConfig.FALLBACK_DNS_ENABLED_KEY] as? Bool ?? false
        self.interceptMatchedDns = conf[ProviderConfig.INTERCEPT_MATCHED_DNS_KEY] as? Bool ?? true
        
        // only update lowPowerMode if present in the stored config, otherwise leave it as the default value
        // (which differs per operating system)
        if let lowPowerMode = conf[ProviderConfig.LOW_POWER_MODE_KEY] as? Bool {
            self.lowPowerMode = lowPowerMode
        }
        self.logLevel = Int(conf[ProviderConfig.LOG_LEVEL_KEY] as? String ?? "3") ?? 3
        self.logTlsuv = conf[ProviderConfig.LOG_TLSUV_KEY] as? Bool ?? false
        
        if let logRotateDaily = conf[ProviderConfig.LOG_ROTATE_DAILY_KEY] as? Bool {
            self.logRotateDaily = logRotateDaily
        }
        if let lrCountStr = conf[ProviderConfig.LOG_ROTATE_COUNT_KEY] as? String, let lrCountInt = Int(lrCountStr) {
            self.logRotateCount = lrCountInt
        }
        if let lrSizeStr = conf[ProviderConfig.LOG_ROTATE_SIZEMB_KEY] as? String, let lrSizeInt = Int(lrSizeStr) {
            self.logRotateSizeMB = lrSizeInt
        }
        return nil
    }
    
    override var debugDescription: String {
        return "ProviderConfig \(self)\n" +
            "ipAddress: \(self.ipAddress)\n" +
            "subnetMask: \(self.subnetMask)\n" +
            "mtu: \(self.mtu)\n" +
            "dns: \(self.dnsAddresses.joined(separator:","))\n" +
            "fallbackDnsEnabled: \(self.fallbackDnsEnabled)\n" +
            "fallbackDns: \(self.fallbackDns)\n" +
            "interceptMatchedDns: \(self.interceptMatchedDns)\n" +
            "lowPowerMode: \(self.lowPowerMode)\n" +
            "logLevel: \(self.logLevel)\n" +
            "logTlsuv: \(self.logTlsuv)\n" +
            "logRotateDaily: \(self.logRotateDaily)\n" +
            "logRotateCount: \(self.logRotateCount)\n" +
            "logRotateSizeMB: \(self.logRotateSizeMB)"
    }
}
