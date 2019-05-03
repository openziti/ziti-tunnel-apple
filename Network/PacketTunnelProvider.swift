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
    let writeLock = NSLock()
    
    override init() {
        super.init()
        self.dnsResolver = DNSResolver(self)
        self.packetRouter = PacketRouter(tunnelProvider:self, dnsResolver: dnsResolver!)
    }
    
    func readPacketFlow() {
        packetFlow.readPacketObjects { (packets:[NEPacket]) in
            guard self.packetRouter != nil else { return }
            for packet in packets {
                self.packetRouter?.route(packet.data)
            }
            self.readPacketFlow()
        }
    }
    
    func writePacket(_ data:Data) {
        //NSLog("Writing packet on thread = \(Thread.current)")
        writeLock.lock()
        if packetFlow.writePackets([data], withProtocols: [AF_INET as NSNumber]) == false {
            NSLog("Error writing packet to TUN")
        }
        writeLock.unlock()
    }
    
    override var debugDescription: String {
        return "PacketTunnelProvider \(self)\n\(self.providerConfig)"
    }
    
    func getNetSessionSync(_ zEdge:ZitiEdge, _ zid:ZitiIdentity, _ svc:ZitiEdgeService,
                           timeOutSecs:TimeInterval=TimeInterval(3.0)) -> Bool {
        
        if let svcId = svc.id {
            let cond = NSCondition()
            cond.lock()
            var updated = false
            svc.networkSession = nil
            zEdge.getNetworkSession(svcId) { _ in updated = true; cond.signal() } // escaping to other thread...
            while !updated {
                if !cond.wait(until: Date(timeIntervalSinceNow: timeOutSecs)) {
                    NSLog("WARN: timed out waiting to get network session for \(zid.name):\(svc.name ?? svcId),")
                    break
                }
            }
            cond.unlock()
            svc.status = ZitiEdgeService.Status(
                Date().timeIntervalSince1970, status: svc.networkSession != nil ? .Available : .PartiallyAvailable )
            return updated
        }
        return false
    }
    
    // Add hostnames to dns, routes to intercept, and set interceptIp
    private func updateHostsAndIntercepts(_ zid:ZitiIdentity, _ svc:ZitiEdgeService) {
        if let hn = svc.dns?.hostname {
            let port = svc.dns?.port ?? 80
            if IPUtils.isValidIpV4Address(hn) {
                let route = NEIPv4Route(destinationAddress: hn,
                                        subnetMask: "255.255.255.255")
                
                // only add if haven't already..
                if interceptedRoutes.first(where: { $0.destinationAddress == route.destinationAddress }) == nil {
                    interceptedRoutes.append(route)
                }
                svc.dns?.interceptIp = "\(hn)"
                NSLog("Adding route for \(zid.name): \(hn) (port \(port))")
            } else {
                // See if we already have this DNS name
                if let currIPs = dnsResolver?.findRecordsByName(hn), currIPs.count > 0 {
                    svc.dns?.interceptIp = "\(currIPs.first!.ip)"
                    NSLog("Using DNS hostname \(hn): \(currIPs.first!.ip) (port \(port))")
                } else if let ipStr = dnsResolver?.addHostname(hn) {
                    svc.dns?.interceptIp = "\(ipStr)"
                    NSLog("Adding DNS hostname \(hn): \(ipStr) (port \(port))")
                } else {
                    NSLog("Unable to add DNS hostname \(hn) for \(zid.name)")
                    svc.status = ZitiEdgeService.Status(Date().timeIntervalSince1970, status: .Unavailable)
                }
            }
        }
    }
    
    private func loadIdentites() -> ZitiError? {
        let zidStore = ZitiIdentityStore()
        let (zids, zErr) = zidStore.loadAll()
        guard zErr == nil, zids != nil else { return zErr }
        
        for zid in zids! {
            if zid.isEnabled == true {
                // Start C SDK's run loop
                if !zid.startRunloop(true) {
                    NSLog("Unable to start run loop for \(zid.name):\(zid.id)")
                    zid.enabled = false
                    zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                } else {
                    let zEdge = ZitiEdge(zid)
                    zid.services?.forEach { svc in
                        svc.status = ZitiEdgeService.Status(Date().timeIntervalSince1970, status: .Available)
                        if !getNetSessionSync(zEdge, zid, svc) {
                            // since startRunloop is blocking, this shouln't happen...
                            NSLog("WARN: unable to get network session for \(zid.id)")
                        }
                        
                        // add hostnames to dns, routes to intercept, and set interceptIp
                        updateHostsAndIntercepts(zid, svc)
                    }
                    zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
                }
                // update the store (continue even if it somehow fails - store method will log any errors)
                _ = zidStore.store(zid)
            }
        }
        self.zids = zids ?? []
        return nil
    }
    
    func getServiceForIntercept(_ ip:String) -> (ZitiIdentity?, ZitiEdgeService?) {
        let splits = ip.split(separator: ":")
        if splits.count != 2 { return (nil, nil) }
        let ipStr = String(splits[0])
        let port = Int(splits[1])
        for zid in zids {
            if zid.isEnabled, let svc = zid.services?.first(where: { $0.dns?.interceptIp == ipStr && $0.dns?.port == port }) {
                return (zid, svc)
            }
        }
        return (nil, nil)
    }
    
    var versionString:String {
        get {
            let verStr = String(cString: ziti_get_version(0)!)
            let gitBranch = String(cString: ziti_git_branch()!)
            let gitCommit = String(cString: ziti_git_commit()!)
            return "\(Version.verboseStr); ziti-sdk-c version \(verStr) @\(gitBranch)(\(gitCommit))"
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Logger.initShared(Logger.TUN_TAG)
        NSLog(versionString)
        
        NSLog("startTunnel: \(Thread.current): \(OperationQueue.current?.underlyingQueue?.label ?? "None")")

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
        let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
        dnsSettings.matchDomains = self.providerConfig.dnsMatchDomains
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        // add dnsServer routes if configured outside of configured subnet
        let net = IPUtils.ipV4AddressStringToData(providerConfig.ipAddress)
        let mask = IPUtils.ipV4AddressStringToData(providerConfig.subnetMask)
        dnsSettings.servers.forEach { svr in
            let dest = IPUtils.ipV4AddressStringToData(svr)
            if IPUtils.inV4Subnet(dest, network: net, mask: mask) == false {
                interceptedRoutes.append(NEIPv4Route(destinationAddress: svr, subnetMask: "255.255.255.255"))
            }
        }
        
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
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            if let error = error {
                NSLog(error.localizedDescription)
                completionHandler(error as NSError)
            }
            
            // packetFlow FD
            var ifname:String?
            let fd = (self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32) ?? -1
            if fd < 0 {
                NSLog("Unable to get tun fd")
            } else {
                var ifnameSz = socklen_t(IFNAMSIZ)
                let ifnamePtr = UnsafeMutablePointer<CChar>.allocate(capacity: Int(ifnameSz))
                ifnamePtr.initialize(repeating: 0, count: Int(ifnameSz))
                if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, ifnamePtr, &ifnameSz) == 0 {
                    ifname = String(cString: ifnamePtr)
                }
                ifnamePtr.deallocate()
            }
            NSLog("Tunnel interface is \(ifname ?? "unknown")")
            
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
        // Just exit - there are bugs in Apple macOS, plus makes sure we're 'clean' on restart
        exit(EXIT_SUCCESS)
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
