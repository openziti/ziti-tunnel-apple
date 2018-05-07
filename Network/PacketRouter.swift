//
//  PacketRouter.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/24/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension
import Foundation

class PacketRouter : NSObject {
    
    let tunnelProvider:PacketTunnelProvider
    let dnsResolver:DNSResolver

    init(tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
        self.dnsResolver = DNSResolver(tunnelProvider)
    }
    
    private func inV4Subnet(_ ip:IPv4Packet) -> Bool {
        let ipAddressData = IPUtils.ipV4AddressStringToData(self.tunnelProvider.providerConfig.ipAddress)
        let subnetMaskData = IPUtils.ipV4AddressStringToData(self.tunnelProvider.providerConfig.subnetMask)
        
        for (dest, (ip, mask)) in zip(ip.destinationAddress, zip(ipAddressData, subnetMaskData)) {
            if (dest & mask) != (ip & mask) {
                return false
            }
        }
        return true
    }
    
    private func routeUDP(_ udp:UDPPacket) {
        NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if self.dnsResolver.needsResolution(udp) {
            dnsResolver.resolve(udp)
        } else {
            // TODO: --> Ziti
            NSLog("...TODO: --> looks meant for Ziti")
        }
    }
    
    func route(_ data:Data) {
        // TODO: IPv4 vs IPv6...
        if let ip = IPv4Packet(data) {
            NSLog("IP-->: \(ip.debugDescription)")
            
            // drop/log any messages that aren't destinated for our subnet (e.g., SSDP broadcast messages)
            if !inV4Subnet(ip) {
                NSLog("...dropping message (not in subnet)")
            } else {
                switch ip.protocolId {
                case IPProtocolId.UDP:
                    if let udp = UDPPacket(ip) {
                        routeUDP(udp)
                    }
                case IPProtocolId.TCP:
                    NSLog("route TCP: TODO...")
                default:
                    NSLog("No route for protocol \(ip.protocolId)")
                }
            }
        }
    }
}
