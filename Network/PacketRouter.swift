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
    
    let tcpConnsLock = NSRecursiveLock()
    var tcpConns:[String:TCPClientConn] = [:]

    init(tunnelProvider:PacketTunnelProvider, dnsResolver:DNSResolver) {
        self.tunnelProvider = tunnelProvider
        self.dnsResolver = dnsResolver
    }
    
    private func routeUDP(_ udp:UDPPacket) {
        //NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if self.dnsResolver.needsResolution(udp) {
            dnsResolver.resolve(udp)
        } else {
            // TODO: --> Ziti
            NSLog("...UDP --> meant for Ziti? UDP not yet supported")
        }
    }
    
    private func routeTCP(_ pkt:TCPPacket) {
        //NSLog("Router routing curr thread = \(Thread.current)")
        //NSLog("TCP-->: \(pkt.debugDescription)")
        
        let intercept = "\(pkt.ip.destinationAddressString):\(pkt.destinationPort)"
        let (zidR, svcR) = tunnelProvider.getServiceForIntercept(intercept)
        guard let zid = zidR, let svc = svcR, let svcName = svc.name else {
            // TODO: find better approach for matched IP but not port
            //    Possibility (for DNS based): store the original IP before intercepting DNS, proxy to it
            //    For non-DNS - hmmm... wonder what happens if I send to intercepted IP. Prob flood myself...
            NSLog("Router: no service found for \(intercept). Dropping packet")
            return
        }
        
        var tcpConn:TCPClientConn
        let key = "TCP:\(pkt.ip.sourceAddressString):\(pkt.sourcePort)->\(zid.name):\(svcName)"
        
        tcpConnsLock.lock()
        if let foundConn = tcpConns[key] {
            tcpConn = foundConn
        } else {
            if pkt.SYN {
                NSLog("Router new session:\(key)\nidentity:\(zid.id), service identity:\(svc.id ?? "unknown")")
                
                // Callback is escaping and will run either in this thread or in another
                tcpConn = TCPClientConn(key, zid, svc, tunnelProvider) { [weak self] respPkt in
                    guard let respPkt = respPkt else {
                        // remove connection
                        NSLog("Router closing con: \(key)")
                        self?.tcpConnsLock.lock()
                        self?.tcpConns.removeValue(forKey: key)
                        self?.tcpConnsLock.unlock()
                        return
                    }
                    //NSLog("<--TCP: \(respPkt.debugDescription)")
                    self?.tunnelProvider.writePacket(respPkt.ip.data)
                }
                tcpConns[key] = tcpConn
            } else if pkt.FIN && pkt.ACK {
                NSLog("FIN ACK for \(key)")
                tcpConnsLock.unlock()
                return
            } else {
                NSLog("Unexpected packet for key \(key)") //"\n\(pkt.debugDescription)")
                tcpConnsLock.unlock()
                return
            }
        }
        tcpConnsLock.unlock()
        
        let state = tcpConn.tcpReceive(pkt)
        if state == TCPClientConn.State.TIME_WAIT || state == TCPClientConn.State.Closed {
            NSLog("Router removing con on state \(state): \(key)")
            tcpConnsLock.lock()
            tcpConns.removeValue(forKey: key)
            tcpConnsLock.unlock()
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
            if let tcp = TCPPacket(ip) {
                routeTCP(tcp)
            }
        default:
            NSLog("No support for protocol \(ip.protocolId)")
        }
    }
}
