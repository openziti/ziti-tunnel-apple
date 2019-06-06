//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import NetworkExtension
import Foundation

class PacketRouter : NSObject {
    let tunnelProvider:PacketTunnelProvider
    let dnsResolver:DNSResolver
    let tcpRunloop:TcpRunloop
    
    init(tunnelProvider:PacketTunnelProvider, dnsResolver:DNSResolver) {
        self.tunnelProvider = tunnelProvider
        self.dnsResolver = dnsResolver
        tcpRunloop = TcpRunloop(tunnelProvider, dnsResolver)
        super.init()
    }
    
    private func routeUDP(_ udp:UDPPacket) {
        //NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if self.dnsResolver.needsResolution(udp) {
            dnsResolver.resolve(udp)
        } else {
            // TODO: --> Ziti
            //NSLog("...UDP --> meant for Ziti? UDP not yet supported")
        }
    }
    
    private func routeTCP(_ data:Data) {
        tcpRunloop.scheduleOp { [weak self] in
            self?.tcpRunloop.tcpStack.received(packet: data)
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
            ip = v4Packet
        case 6:
            guard let v6Packet = IPv6Packet(data) else {
                NSLog("Unable to create IPv6Packet from data")
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
            /*if let tcp = TCPPacket(ip) {
                routeTCP(tcp)
            }*/
            routeTCP(data)
        default:
            NSLog("No support for protocol \(ip.protocolId)")
        }
    }
}
