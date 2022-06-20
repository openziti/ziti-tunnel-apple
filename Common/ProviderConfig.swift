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

    var description: String {
        switch self {
        case .invalidIpAddress: return "Invalid IP Address (expect valid IPv4 address)"
        case .invalidSubnetMask: return "Invalid Subnet Mask (axpect valid IPv4 subnet mask)"
        case .invalidMtu: return "Invalid MTU"
        case .invalidDnsAddresses: return "Invalid DNS Addresses (expect comma-delimited list of IPv4 addresses)"
        case .invalidFallbackDns: return "Invalid Fallback DNS (expect valid IPv4 address"
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
    static var ENABLE_MFA_KEY = "enableMfa"
    static var LOG_LEVEL = "logLevel"
    
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
    var interceptMatchedDns:Bool = true
    var enableMfa:Bool = false
    
    //TODO: Placeholder for now - need to make configurable & store (and setable in UI at least for ZME)...
    var lowPowerMode:Bool = false
    
    func createDictionary() -> ProviderConfigDict {
        return [ProviderConfig.IP_KEY: self.ipAddress,
                ProviderConfig.SUBNET_KEY: self.subnetMask,
                ProviderConfig.MTU_KEY: String(self.mtu),
                ProviderConfig.LOG_LEVEL: String(self.logLevel),
                ProviderConfig.DNS_KEY: self.dnsAddresses.joined(separator: ","),
                ProviderConfig.FALLBACK_DNS_ENABLED_KEY: self.fallbackDnsEnabled,
                ProviderConfig.FALLBACK_DNS_KEY: self.fallbackDns,
                ProviderConfig.ENABLE_MFA_KEY: self.enableMfa,
                ProviderConfig.INTERCEPT_MATCHED_DNS_KEY: self.interceptMatchedDns]
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
        self.enableMfa = conf[ProviderConfig.ENABLE_MFA_KEY] as? Bool ?? false
        self.logLevel = Int(conf[ProviderConfig.LOG_LEVEL] as? String ?? "3") ?? 3
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
            "enableMfa: \(self.enableMfa)\n" +
            "logLevel: \(self.logLevel)"
    }
}
