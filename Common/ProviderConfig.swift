//
//  Configuration.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

enum ProviderConfigError : Error {
    case invalidIpAddress
    case invalidSubnetMask
    case invalidMtu
    case invalidDnsAddresses
    case invalidMatchDomains
    case invalidDnsProxyAdddresses
    
    var description: String {
        switch self {
        case .invalidIpAddress: return "Invalid IP Address (expect valid IPv4 address)"
        case .invalidSubnetMask: return "Invalid Subnet Mask (axpect valid IPv4 subnet mask)"
        case .invalidMtu: return "Invalid MTU"
        case .invalidDnsAddresses: return "Invalid DNS Addresses (expect comma-delimited list of IPv4 addresses)"
        case .invalidMatchDomains: return "Invalid DNS Match Domains (expect comma-delimited list of domains)"
        case .invalidDnsProxyAdddresses: return "Invalid Onwatd DNS Addresses (expect comma-delimited list of IPv4 addresses)"
        }
    }
}

typealias ProviderConfigDict = [String : Any]

class ProviderConfig : NSObject {
    static let providerBundleIdentifier = "com.ampifyllc.ZitiPacketTunnel.PacketTunnelProvider"
    
    static var IP_KEY = "ip"
    static var SUBNET_KEY = "subnet"
    static var MTU_KEY = "mtu"
    static var DNS_KEY = "dns"
    static var MATCH_DOMAINS_KEY = "matchDomains"
    static var DNS_PROXIES_KEY = "dnsProxies"
    
    // some defaults in case .mobileconfig not used
    var ipAddress:String = "169.254.126.1"
    var subnetMask:String = "255.255.255.0"
    var mtu:Int = 1500
    var dnsAddresses:[String] = ["169.254.126.2"]
    var dnsMatchDomains:[String] = [""]
    var dnsProxyAddresses:[String] = ["1.1.1.1, 1.0.0.1"]
    
    var serverAddress = "169.254.126.255"
    var username = "NetFoundry"
    var localizedDescription = "Ziti Packet Tunnel"
    
    func createDictionary() -> ProviderConfigDict {
        return [ProviderConfig.IP_KEY: self.ipAddress,
            ProviderConfig.SUBNET_KEY: self.subnetMask,
            ProviderConfig.MTU_KEY: String(self.mtu),
            ProviderConfig.DNS_KEY: self.dnsAddresses.joined(separator: ","),
            ProviderConfig.MATCH_DOMAINS_KEY: self.dnsMatchDomains.joined(separator: ","),
            ProviderConfig.DNS_PROXIES_KEY: self.dnsProxyAddresses.joined(separator: ",")]
    }
    
    private func isValidIpAddress(_ obj:Any?) -> Bool {
        if (obj == nil) { return false }
        let addr = (obj as! String).trimmingCharacters(in: .whitespaces)
        let parts = addr.components(separatedBy: ".")
        let nums = parts.compactMap { Int($0) }
        return parts.count == 4 && nums.count == 4 && nums.filter { $0 >= 0 && $0 < 256}.count == 4
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
        
        if let dns = conf[ProviderConfig.DNS_PROXIES_KEY] {
            let dnsArray = (dns as! String).components(separatedBy: ",")
            if dnsArray.count == 0 || dnsArray.contains { !isValidIpAddress($0) } {
                return ProviderConfigError.invalidDnsProxyAdddresses
            }
        } else {
            return ProviderConfigError.invalidDnsProxyAdddresses
        }
        
        if (Int(conf[ProviderConfig.MTU_KEY] as! String) == nil) {
            return ProviderConfigError.invalidMtu
        }
        
        return nil
    }
    
    func parseDictionary(_ conf:ProviderConfigDict) -> ProviderConfigError? {
        
        if let error = validateDictionaty(conf) {
            return error
        }
        
        self.ipAddress = conf[ProviderConfig.IP_KEY] as! String
        self.subnetMask = conf[ProviderConfig.SUBNET_KEY] as! String
        self.mtu = Int(conf[ProviderConfig.MTU_KEY] as! String)!
        self.dnsAddresses = (conf[ProviderConfig.DNS_KEY] as! String).components(separatedBy: ",")
    
        self.dnsMatchDomains = (conf[ProviderConfig.MATCH_DOMAINS_KEY] as! String).components(separatedBy: ",")
        if self.dnsMatchDomains.count == 0 {
            self.dnsMatchDomains = [""] // all routes...
        }
        self.dnsProxyAddresses = (conf[ProviderConfig.DNS_PROXIES_KEY] as! String).components(separatedBy: ",")
    
        return nil
    }
    
    override var debugDescription: String {
        return "ProviderConfig \(self)\n" +
            "ipAddress: \(self.ipAddress)\n" +
            "subnetMask: \(self.subnetMask)\n" +
            "mtu: \(self.mtu)\n" +
            "dns: \(self.dnsAddresses.joined(separator:","))\n" +
            "dnsMatchDomains: \(self.dnsMatchDomains.joined(separator:","))\n" +
            "dnsProxies \(self.dnsProxyAddresses.joined(separator:","))"
    }
}
