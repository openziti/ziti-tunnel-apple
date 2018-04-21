//
//  PacketTunnelProvider.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension

enum ZitiPacketTunnelError : Error {
    case configurationError
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    var conf = [String: AnyObject]()
    
    func readPacketFlow() {
        self.packetFlow.readPacketObjects { (packets:[NEPacket]) in
            NSLog("Got \(packets.count) packets!")
            for packet:NEPacket in packets {
                NSLog("   protocolFamily: \(packet.protocolFamily)")
                if let metadata = packet.metadata {
                    NSLog("   metatadata.sourceApp: \(metadata.sourceAppSigningIdentifier)")
                } else {
                    NSLog("   metadata: nil")
                }
                
                if let ipPacket = IPv4Packet(data:packet.data) {
                    NSLog("\(ipPacket.debugDescription)")
                    
                    if (ipPacket.protocolId == UInt8(IPPROTO_UDP)) {
                        if let udp = UDPPacket(ipPacket) {
                            NSLog("\(udp.debugDescription)")
                            if udp.destinationPort == 53 {
                                if let dns = DNSPacket(udp) {
                                    NSLog("\(dns.debugDescription)")
                                }
                                //let udpR = UDPPacket(udp, payload:udp.payload)
                                //NSLog("UDP-R: \(udpR.debugDescription)")
                                //NSLog("IP-R: \(udpR.ip.debugDescription)")
                            }
                        }
                    }
                }
                
                /*
                let ipPacket = IPv4Packet()
                
                do {
                    try ipPacket.loadPacket(packet)
                    NSLog("   \(ipPacket.debugDescription)")
                    
                    if let udpP = ipPacket.udpPacket {
                        NSLog("   \(udpP.debugDescription)")
                        
                        if let dnsP = udpP.dnsPacket {
                            // TODO: If Query, class 1, type 1 and we care, respond
                            if dnsP.qrFlag == 0 && dnsP.questions.count > 0 {
                                for q in dnsP.questions {
                                    if q.qClass == 0x01 && q.qType == 0x01 {
                                        if q.qName == "dave.services.netfoundry.io" {
                                            NSLog("GOTCHA DAVE!")
                                            
                                            // Switch SRC and DEST in IP and UDP. Didle flags, Tack on the answer, write to TUN
                                        }
                                    }
                                }
                            }
                            // else, forward to upstream DNS and respond
                        }
                    }
                } catch {
                    NSLog("   Error loading IP Packet")
                }
 */
                
                // note: if dest is our dns server, need to see if its for our routes (169.254/16).  If dest if
                // somewhere else, drop it (e.g., see multicast, netbios stuff...).  If its one of our routes, off we go...
            }
            self.readPacketFlow()
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        NSLog("startTunnel")
        
        conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as [String : AnyObject]
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        
        if let ip = conf["ip"], let subnet = conf["subnet"], let mtu = conf["mtu"], let dns = conf["dns"] {
            
            tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [ip as! String],
                                                                subnetMasks: [subnet as! String])
            
            let includedRoute = NEIPv4Route(destinationAddress: ip as! String,
                                            subnetMask: subnet as! String)
            
            tunnelNetworkSettings.ipv4Settings?.includedRoutes = [includedRoute]
            tunnelNetworkSettings.mtu = Int(mtu as! String) as NSNumber?
            
            let dnsSettings = NEDNSSettings(servers: (dns as! String).components(separatedBy: ","))
            if let matchDomains = conf["matchDomains"] {
                dnsSettings.matchDomains = (matchDomains as! String).components(separatedBy: ",")
            } else {
                dnsSettings.matchDomains = [""]
            }
            tunnelNetworkSettings.dnsSettings = dnsSettings
            
        } else {
            NSLog("Invalid configuration")
            completionHandler(ZitiPacketTunnelError.configurationError)
            return
        }
        
        NSLog("dnsSettings.matchDomains = \(String(describing: tunnelNetworkSettings.dnsSettings?.matchDomains))")

        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            if let error = error {
                NSLog(error.localizedDescription)
                // TODO: status and get outta here
            }
            
            // if all good, start listening for for ziti protocol..
        }
        
        // call completion handler with nil to indicate success (TODO: better approach would be make sure we
        // get a bit further along...)
        completionHandler(nil)
        
        //
        // Start listening for traffic headed our way via the tun interface
        //
        readPacketFlow();
        
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("stopTunnel")

        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let messageString = NSString(data: messageData, encoding: String.Encoding.utf8.rawValue) else {
            completionHandler?(nil)
            return
        }
        NSLog("PTP Got message from app... \(messageString)")
        
        if let handler = completionHandler {
            handler(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
}
