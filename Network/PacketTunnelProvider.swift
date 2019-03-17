//
//  PacketTunnelProvider.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    let providerConfig = ProviderConfig()
    var packetRouter:PacketRouter?
    var dnsResolver:DNSResolver?
    var interceptedRoutes:[NEIPv4Route] = []
    var zids:[ZitiIdentity] = []
    
    override init() {
        NSLog("tun init")
        super.init()
        self.dnsResolver = DNSResolver(self)
        self.packetRouter = PacketRouter(tunnelProvider:self, dnsResolver: dnsResolver!)
    }
    
    func readPacketFlow() {
        self.packetFlow.readPacketObjects { (packets:[NEPacket]) in
            guard self.packetRouter != nil else { return }
            for packet in packets {
                self.packetRouter?.route(packet.data)
            }
            self.readPacketFlow()
        }
    }
    
    override var debugDescription: String {
        return "PacketTunnelProvider \(self)\n\(self.providerConfig)"
    }
    
    func loadIdentites() -> ZitiError? {
        let zidStore = ZitiIdentityStore()
        let (zids, zErr) = zidStore.loadAll()
        guard zErr == nil, zids != nil else { return zErr }
        
        zids!.forEach { zid in
            zid.services?.forEach { svc in
                if let hn = svc.dns?.hostname {
                    if IPUtils.isValidIpV4Address(hn) {
                        let route = NEIPv4Route(destinationAddress: hn,
                                                subnetMask: "255.255.255.255")
                        interceptedRoutes.append(route)
                        NSLog("Adding route for \(zid.name): \(hn)")
                    } else {
                        if let ipStr = dnsResolver?.addHostname(hn) {
                            NSLog("Adding DNS hostname \(hn): \(ipStr)")
                        } else {
                            NSLog("Unable to add DNS hostname \(hn)")
                        }
                    }
                }
            }
        }
        self.zids = zids ?? []
        return nil
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("startTunnel")
        let conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as ProviderConfigDict
        if let error = self.providerConfig.parseDictionary(conf) {
            NSLog("Unable to startTunnel. Invalid providerConfiguration. \(error)")
            completionHandler(error)
            return
        }
        NSLog("\(self.providerConfig.debugDescription)")
        
        // load identities
        // for each svc aither update intercepts or add hostname to resolver
        if let idLoadErr = loadIdentites() {
            completionHandler(idLoadErr)
            return
        }
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [self.providerConfig.ipAddress],
                                                            subnetMasks: [self.providerConfig.subnetMask])
        let includedRoute = NEIPv4Route(destinationAddress: self.providerConfig.ipAddress,
                                        subnetMask: self.providerConfig.subnetMask)
        interceptedRoutes.append(includedRoute)
        interceptedRoutes.forEach { r in
            NSLog("route: \(r.destinationAddress) / \(r.destinationSubnetMask)")
        }
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = interceptedRoutes
        // TODO: ipv6Settings
        tunnelNetworkSettings.mtu = self.providerConfig.mtu as NSNumber
        
        let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
        dnsSettings.matchDomains = self.providerConfig.dnsMatchDomains
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            if let error = error {
                NSLog(error.localizedDescription)
                completionHandler(error as NSError)
            }
            
            // call completion handler with nil to indicate success
            completionHandler(nil)
            
            //
            // Start listening for traffic headed our way via the tun interface
            //
            self.readPacketFlow()
        }
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
