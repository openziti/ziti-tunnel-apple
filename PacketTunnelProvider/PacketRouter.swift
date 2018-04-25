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
    
    private func inSubnet(_ ip:IPv4Packet) -> Bool {
        let conf = self.tunnelProvider.conf
        if let ipAddress = conf["ip"], let subnetMask = conf["subnet"] {
            let ipAddressData = IPv4Utils.ipAddressStringToData(ipAddress as! String)
            let subnetMaskData = IPv4Utils.ipAddressStringToData(subnetMask as! String)
            
            for (dest, (ip, mask)) in zip(ip.destinationAddress, zip(ipAddressData, subnetMaskData)) {
                if (dest & mask) != (ip & dest) {
                    return false
                }
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
        if let ip = IPv4Packet(data) {
            NSLog("IP-->: \(ip.debugDescription)")
            
            // drop/log any messages that aren't destinated for our subnet (e.g., SSDP broadcast messages)
            if !inSubnet(ip) {
                NSLog("...dropping message (not in subnet)")
            } else {
                switch ip.protocolId {
                case IPv4ProtocolId.UDP:
                    if let udp = UDPPacket(ip) {
                        routeUDP(udp)
                    }
                case IPv4ProtocolId.TCP:
                    NSLog("route TCP: TODO...")
                default:
                    NSLog("No route for protocol \(ip.protocolId)")
                }
            }
        }
    }
}
