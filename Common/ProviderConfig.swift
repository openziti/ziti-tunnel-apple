//
//  Configuration.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

enum ProviderConfigError : Error {
    case invalidConfig
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
    var mtu:Int = 2000
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
    
    func parseDictionary(_ conf:ProviderConfigDict) throws {
        if let ip = conf[ProviderConfig.IP_KEY] { self.ipAddress = ip as! String }
        if let subnet = conf[ProviderConfig.SUBNET_KEY] { self.subnetMask = subnet as! String }
        if let mtu = conf[ProviderConfig.MTU_KEY] { self.mtu = Int(mtu as! String)! }
        if let dns = conf[ProviderConfig.DNS_KEY] { self.dnsAddresses = (dns as! String).components(separatedBy: ",") }
        
        if let matchDomains = conf[ProviderConfig.MATCH_DOMAINS_KEY] {
            self.dnsMatchDomains = (matchDomains as! String).components(separatedBy: ",")
        } else {
            self.dnsMatchDomains = [""] // all routes...
        }
        
        if let dnsProxies = conf[ProviderConfig.DNS_PROXIES_KEY] {
            self.dnsProxyAddresses = (dnsProxies as! String).components(separatedBy: ",")
        }
        
        // TODO: sanity checks / defaults on each... (e.g., valid ip address, if matchDomains=all make sure we have proxy
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
