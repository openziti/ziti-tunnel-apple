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
    
    var packetRouter:PacketRouter? = nil
    
    var ipAddress:String = "169.254.126.1"
    var subnetMask:String = "255.255.255.0"
    var mtu:Int = 2000
    var dnsAddresses:[String] = ["169.254.126.2"]
    var dnsMatchDomains:[String] = []
    var dnsProxyAddresses:[String] = ["1.1.1.1", "1.0.0.1"]
    
    func readPacketFlow() {
        self.packetFlow.readPacketObjects { (packets:[NEPacket]) in
            
            guard let pr = self.packetRouter else {
                NSLog("PacketTunnelProvider: invalid packet router.")
                return
            }
            
            NSLog("Got \(packets.count) packets!")
            for packet:NEPacket in packets {
                if packet.protocolFamily == AF_INET {
                    pr.route(packet.data)
                } else {
                    NSLog("...ignoring non AF_INET packet, protocolFamily=\(packet.protocolFamily)")
                }
            }
            self.readPacketFlow()
        }
    }
    
    private func parseConf(_ conf:[String:AnyObject]) -> Bool {
        if let ip = conf["ip"] { self.ipAddress = ip as! String }
        if let subnet = conf["subnet"] { self.subnetMask = subnet as! String }
        if let mtu = conf["mtu"] { self.mtu = Int(mtu as! String)! }
        if let dns = conf["dns"] { self.dnsAddresses = (dns as! String).components(separatedBy: ",") }
        
        if let matchDomains = conf["matchDomains"] {
            self.dnsMatchDomains = (matchDomains as! String).components(separatedBy: ",")
        } else {
            self.dnsMatchDomains = [""] // all routes...
        }
        
        if let dnsProxies = conf["dnsProxies"] {
            self.dnsProxyAddresses = (dnsProxies as! String).components(separatedBy: ",")
        }
        
        // TODO: sanity checks / defaults on each... (e.g., valid ip address, if matchDomains=all make sure we have proxy
        return true
    }
    
    override var debugDescription: String {
        var str = "PacketTunnelProvider \(self)"
        
        str += "\n" +
            "ipAddress: \(self.ipAddress)\n" +
            "subnetMask: \(self.subnetMask)\n" +
            "mtu: \(self.mtu)\n" +
            "dns: \(self.dnsAddresses.joined(separator:","))\n" +
            "dnsMatchDomains: \(self.dnsMatchDomains.joined(separator:","))\n" +
            "dnsProxies \(self.dnsProxyAddresses.joined(separator:","))"
        
        return str
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        NSLog("startTunnel")
        
        let conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as [String : AnyObject]
        if parseConf(conf) != true {
            NSLog("Unable to startTunnel. Invalid providerConfiguration")
            completionHandler(ZitiPacketTunnelError.configurationError)
            return
        }
        
        NSLog(self.debugDescription)
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        
        tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [self.ipAddress],
                                                            subnetMasks: [self.subnetMask])
        
        let includedRoute = NEIPv4Route(destinationAddress: self.ipAddress,
                                        subnetMask: self.subnetMask)
        
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = [includedRoute]
        tunnelNetworkSettings.mtu = self.mtu as NSNumber
        
        let dnsSettings = NEDNSSettings(servers: self.dnsAddresses)
        dnsSettings.matchDomains = self.dnsMatchDomains
        //dnsSettings.matchDomains = [""] to be the default domain
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            if let error = error {
                NSLog(error.localizedDescription)
                // TODO: status and get outta here
            }
            
            // if all good, start listening for for ziti protocol..
        }
        
        self.packetRouter = PacketRouter(tunnelProvider:self)
        
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

        self.packetRouter = nil
        
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
