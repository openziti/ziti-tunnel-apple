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
    
    // TODO: when we add intercept routes we'll need to check those too...
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
        //NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if self.dnsResolver.needsResolution(udp) {
            dnsResolver.resolve(udp)
        } else {
            // TODO: --> Ziti
            NSLog("...TODO: --> looks meant for Ziti")
        }
    }
    
    private func createIPPacket(_ data:Data) -> IPPacket? {
        let ip:IPPacket
        
        guard data.count > 0 else {
            NSLog("Invalid (empty) data for IPPacket")
            return nil
        }
        
        let version = data[0] >> 4
        switch version {
        case 4:
            guard let v4Packet = IPv4Packet(data) else {
                NSLog("Unable to create IPv4Packet from data")
                return nil
            }
            guard inV4Subnet(v4Packet) else {
                NSLog("...dropping v4 Packet (not in subnet)") // (e.g., SSDP broadcast messages)
                return nil
            }
            ip = v4Packet
        case 6:
            guard let v6Packet = IPv6Packet(data) else {
                NSLog("Unable to create IPv6Packet from datae")
                return nil
            }
            ip = v6Packet
        default:
            NSLog("Unable to create IPPacket from data. Unrecocognized IP version")
            return nil
        }
        return ip
    }
    
    func route(_ data:Data) {
        guard let ip = self.createIPPacket(data) else {
            NSLog("Unable to create IPPacket for routing")
            return
        }
        
        //NSLog("IP-->: \(ip.debugDescription)")
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
