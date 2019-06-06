//
// Copyright © 2019 NetFoundry Inc. All rights reserved
//

import Foundation
import NetworkExtension

enum ProviderConfigError : Error {
    case invalidIpAddress
    case invalidSubnetMask
    case invalidMtu
    case invalidDnsAddresses
    case invalidMatchDomains

    var description: String {
        switch self {
        case .invalidIpAddress: return "Invalid IP Address (expect valid IPv4 address)"
        case .invalidSubnetMask: return "Invalid Subnet Mask (axpect valid IPv4 subnet mask)"
        case .invalidMtu: return "Invalid MTU"
        case .invalidDnsAddresses: return "Invalid DNS Addresses (expect comma-delimited list of IPv4 addresses)"
        case .invalidMatchDomains: return "Invalid DNS Match Domains (expect comma-delimited list of domains)"
        }
    }
}

typealias ProviderConfigDict = [String : Any]

class ProviderConfig : NSObject {
    
    static var IP_KEY = "ip"
    static var SUBNET_KEY = "subnet"
    static var MTU_KEY = "mtu"
    static var DNS_KEY = "dns"
    static var MATCH_DOMAINS_KEY = "matchDomains"
    
    // some defaults in case .mobileconfig not used
    var ipAddress:String = "169.254.0.1"
    var subnetMask:String = "255.255.255.0"
    #if os(macOS)
    var mtu:Int = 16000
    #else
    var mtu:Int = 4000
    #endif
    var dnsAddresses:[String] = ["169.254.0.2"]
    var dnsMatchDomains:[String] = [""]
    var username = "Ziti"
    var localizedDescription = "NetFoundry"
    
    func createDictionary() -> ProviderConfigDict {
        return [ProviderConfig.IP_KEY: self.ipAddress,
            ProviderConfig.SUBNET_KEY: self.subnetMask,
            ProviderConfig.MTU_KEY: String(self.mtu),
            ProviderConfig.DNS_KEY: self.dnsAddresses.joined(separator: ","),
            ProviderConfig.MATCH_DOMAINS_KEY: self.dnsMatchDomains.joined(separator: ",")]
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
        if let dns = conf[ProviderConfig.DNS_KEY] {
            let dnsArray = (dns as! String).components(separatedBy: ",")
            if dnsArray.count == 0 || dnsArray.contains { !isValidIpAddress($0) } {
                return ProviderConfigError.invalidDnsAddresses
            }
        } else {
            return ProviderConfigError.invalidDnsAddresses
        }
        if (Int(conf[ProviderConfig.MTU_KEY] as! String) == nil) {
            return ProviderConfigError.invalidMtu
        }
        return nil
    }
    
    func parseDictionary(_ conf:ProviderConfigDict) -> ProviderConfigError? {
        if let error = validateDictionaty(conf) { return error }
        self.ipAddress = (conf[ProviderConfig.IP_KEY] as! String).trimmingCharacters(in: .whitespaces)
        self.subnetMask = (conf[ProviderConfig.SUBNET_KEY] as! String).trimmingCharacters(in: .whitespaces)
        self.mtu = Int(conf[ProviderConfig.MTU_KEY] as! String)!
        self.dnsAddresses = (conf[ProviderConfig.DNS_KEY] as! String).trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
        self.dnsMatchDomains = [""] // all routes by default
        if let mds = conf[ProviderConfig.MATCH_DOMAINS_KEY] {
            let mdsArray = (mds as! String).trimmingCharacters(in: .whitespaces).components(separatedBy: ",")
            if mdsArray.count > 0 {
                self.dnsMatchDomains = mdsArray
            }
        }
        return nil
    }
    
    override var debugDescription: String {
        return "ProviderConfig \(self)\n" +
            "ipAddress: \(self.ipAddress)\n" +
            "subnetMask: \(self.subnetMask)\n" +
            "mtu: \(self.mtu)\n" +
            "dns: \(self.dnsAddresses.joined(separator:","))\n" +
            "dnsMatchDomains: \(self.dnsMatchDomains.joined(separator:","))"
    }
}
