//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import NetworkExtension
import Network
import CZiti

class ZitiTunnelConfig : Codable {
    static var configType = "ziti-tunneler-client.v1"
    
    let hostname:String
    let port:Int
    
    static func parseConfig(_ zs: inout ziti_service) -> ZitiTunnelConfig? {
        if let cfg = ziti_service_get_raw_config(&zs, ZitiTunnelConfig.configType.cString(using: .utf8)) {
            return try? JSONDecoder().decode(ZitiTunnelConfig.self, from: Data(String(cString: cfg).utf8))
        }
        return nil
    }
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    let providerConfig = ProviderConfig()
    var dnsResolver:DNSResolver?
    var interceptedRoutes:[NEIPv4Route] = []
    var zids:[ZitiIdentity] = []    
    var netifDriver:NetifDriver!
    var tnlr_ctx:tunneler_context?
    var loop:UnsafeMutablePointer<uv_loop_t>!
    var writeLock = NSLock()
    
    override init() {
        super.init()
        self.dnsResolver = DNSResolver(self)
        self.netifDriver = NetifDriver(ptp: self)
    }
    
    func readPacketFlow() {
        packetFlow.readPacketObjects { (packets:[NEPacket]) in
            for packet in packets {
                if packet.data.count > 0 {
                    var isDNS = false
                    let version = packet.data[0] >> 4
                    if version == 4 {
                        if let ip = IPv4Packet(packet.data),
                            ip.protocolId == IPProtocolId.UDP,
                            let udp = UDPPacket(ip),
                            let dnsResolver = self.dnsResolver,
                            dnsResolver.needsResolution(udp) {
                            
                            isDNS = true
                            dnsResolver.resolve(udp)
                        }
                    }
                    if !isDNS {
                        self.netifDriver.queuePacket(packet.data)
                    }
                }
            }
            self.readPacketFlow()
        }
    }
    
    func writePacket(_ data:Data) {
        writeLock.lock()
        packetFlow.writePackets([data], withProtocols: [AF_INET as NSNumber])
        writeLock.unlock()
    }
    
    override var debugDescription: String {
        return "PacketTunnelProvider \(self)\n\(self.providerConfig)"
    }
    
    // Add hostnames to dns, routes to intercept, and set interceptIp
    private func updateHostsAndIntercepts(_ zid:ZitiIdentity, _ svc:ZitiService) {
        
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
                NSLog("***** Not ***** Adding route for \(zid.name): \(hn) (port \(port))")
            } else {
                dnsResolver?.hostnamesLock.lock()
                // See if we already have this DNS name
                if let currIPs = dnsResolver?.findRecordsByName(hn), currIPs.count > 0 {
                    svc.dns?.interceptIp = "\(currIPs.first!.ip)"
                    NSLog("Using DNS hostname \(hn): \(currIPs.first!.ip) (port \(port))")
                } else if let ipStr = dnsResolver?.addHostname(hn) {
                    svc.dns?.interceptIp = "\(ipStr)"
                    NSLog("Adding DNS hostname \(hn): \(ipStr) (port \(port))")
                } else {
                    NSLog("Unable to add DNS hostname \(hn) for \(zid.name)")
                    svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Unavailable)
                }
                dnsResolver?.hostnamesLock.unlock()
            }
        }
    }
    
    private func countInterceptRefs(_ zids:[ZitiIdentity], _ interceptIp:String) -> Int {
        var count = 0
        zids.forEach { zid in
            zid.services.forEach { svc in
                if let svcInterceptIp = svc.dns?.interceptIp, svcInterceptIp == interceptIp {
                    count += 1
                }
            }
        }
        return count
    }
    
    private func loadIdentites(_ loop:UnsafeMutablePointer<uv_loop_t>) -> ZitiError? {
        let zidStore = ZitiIdentityStore()
        let (zids, zErr) = zidStore.loadAll()
        guard zErr == nil, zids != nil else { return zErr }
                
        for zid in zids! {
            if let czid = zid.czid, zid.isEnabled == true {
                
                // blank out services before registering to hear back what they are..
                zid.services = []
                
                let ziti = Ziti(zid: czid, loop: loop)
                let nameWas = czid.name
                
                ziti.run { zErr in
                    guard zErr == nil else {
                        NSLog("Unable to init \(zid.name):\(zid.id), err: \(zErr!.localizedDescription)")
                        zid.enabled = false
                        zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                        return
                    }
                                        
                    if czid.name != nameWas {
                        _ = zidStore.store(zid)
                    }
                    
                    let (cvers, _, _) = ziti.getControllerVersion()
                    let cVersion = "\(cvers)"
                    if zid.controllerVersion != cVersion {
                        zid.controllerVersion = cVersion
                        _ = zidStore.store(zid)
                    }
                    
                    // forces reference to ziti to be kept by ziti.  generally not a great idea, but fine
                    // for us since we want the ziti instance to exist for the entire run (new or deleted
                    // identities cause tunnel to be restarted). will need to change this to a weak reference
                    // to `ziti` if we change from restarting on add/delete of identities, and add management
                    // of `ziti` lifecycle...
                    ziti.registerServiceCallback { [weak self] ztx, zs, status in
                        
                        guard var zs = zs?.pointee, let self = self else { return }
                        
                        // C SDK currently grabs all services in single call.  Eventtually it'll be
                        // paginated, but for now, once C SDK reports on a single service it knows about
                        // all of 'em.  So ziti_dump() here should have lots of useful info.
                        // note also another string referene to ziti that should be clean-up when we
                        // change from restarting the tunnel on new/deleted identities
                        if zid.services.count == 0 { ziti.dump() }
                        
                        let serviceName = String(cString: zs.name)
                        let serviceId = String(cString: zs.id)
                        let serviceWas = zid.services.first(where: { $0.id == serviceId })
                        
                        if status == ZITI_OK && ((zs.perm_flags & ZITI_CAN_DIAL) != 0) {
                            if let cfg = ZitiTunnelConfig.parseConfig(&zs) {
                                NSLog("Service Available \(zid.name)::\(serviceName)")
                                
                                if let svc = serviceWas {
                                    // Update all fields except interceptIP
                                    svc.name = serviceName
                                    
                                    // if dns changed we need to update DNS hostnames
                                    if svc.dns?.hostname != cfg.hostname {
                                        if self.countInterceptRefs(zids!, svc.dns?.interceptIp ?? "") == 1 {
                                            if let interceptIp = svc.dns?.interceptIp, let dnsResolver = self.dnsResolver {
                                                let hn = svc.dns?.hostname ?? ""
                                                NSLog("Removing DNS entry for service \(serviceName), \(hn) != \(interceptIp)")
                                                dnsResolver.hostnamesLock.lock()
                                                dnsResolver.hostnames = dnsResolver.hostnames.filter { $0.ip != interceptIp }
                                                dnsResolver.hostnamesLock.unlock()
                                            }
                                        }
                                        svc.dns?.hostname = cfg.hostname
                                        self.updateHostsAndIntercepts(zid, svc)
                                    }
                                    svc.dns?.port = cfg.port
                                    
                                    // remove intercept
                                    ziti_tunneler_stop_intercepting(self.tnlr_ctx, zs.id)
                                    
                                    // add it back with new info
                                    if let interceptIp = svc.dns?.interceptIp {
                                        NSLog("Updating intercept for \(serviceName), \(cfg.hostname)->\(interceptIp)")
                                        ziti_tunneler_intercept_v1(self.tnlr_ctx, UnsafeRawPointer(ztx), zs.id, zs.name, interceptIp.cString(using: .utf8), Int32(cfg.port))
                                    }
                                    svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Unavailable)
                                } else {
                                    let newSvc = ZitiService()
                                    newSvc.name = serviceName
                                    newSvc.id = serviceId
                                    newSvc.dns = ZitiService.Dns()
                                    newSvc.dns?.hostname = cfg.hostname
                                    newSvc.dns?.port = cfg.port
                                    
                                    self.updateHostsAndIntercepts(zid, newSvc)
                                    if let interceptIp = newSvc.dns?.interceptIp {
                                        NSLog("Adding intercept for \(serviceName), \(cfg.hostname)->\(interceptIp)")
                                        ziti_tunneler_intercept_v1(self.tnlr_ctx, UnsafeRawPointer(ztx), zs.id, zs.name, interceptIp.cString(using: .utf8), Int32(cfg.port))
                                    }
                                    newSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available)
                                    zid.services.append(newSvc)
                                }
                            } else {
                                NSLog("Unable to parse config for serivce \(serviceName):\(serviceId)")
                            }
                        } else if status == ZITI_SERVICE_UNAVAILABLE {
                            NSLog("Service Unvailable \(zid.name)::\(serviceName)")
                            
                            let refCount = self.countInterceptRefs(zids!, serviceWas?.dns?.interceptIp ?? "")
                            if refCount == 1 {
                                // remove from hostnames (locked) TODO: move DNS stuff into DnsResolver
                                if let interceptIp = serviceWas?.dns?.interceptIp, let dnsResolver = self.dnsResolver {
                                    let hn = serviceWas?.dns?.hostname ?? ""
                                    NSLog("Removing DNS entry for service \(serviceName), \(hn) != \(interceptIp)")
                                    dnsResolver.hostnamesLock.lock()
                                    dnsResolver.hostnames = dnsResolver.hostnames.filter { $0.ip != interceptIp }
                                    dnsResolver.hostnamesLock.unlock()
                                }
                            } else {
                                NSLog("Leaving DNS entry, refCount was \(refCount)")
                            }
                            ziti_tunneler_stop_intercepting(self.tnlr_ctx, zs.id)
                            zid.services = zid.services.filter { $0.id != serviceId }
                        }
                        zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
                        _ = zidStore.store(zid)
                    }
                }
            }
        }
        self.zids = zids ?? []
        return nil
    }
    
    var versionString:String {
        get {
            let z = Ziti(withId: CZiti.ZitiIdentity(id: "", ztAPI: ""))
            let (vers, rev, buildDate) = z.getCSDKVersion()
            return "\(Version.verboseStr); ziti-sdk-c version \(vers)-\(rev)(\(buildDate))"
        }
    }
    
    static let dummy:uv_async_cb = { h in }
    @objc func runZiti() {
        // put something on the loop to hold it open for now. TODO:should be able to remove once NetifDriver is running
        var h = uv_async_t()
        uv_async_init(loop, &h, PacketTunnelProvider.dummy)
                
        // make sure we have netif setup before reurning or starting run loop
        var tunneler_opts = tunneler_sdk_options(
            netif_driver: self.netifDriver.open(),
            ziti_dial: ziti_sdk_c_dial,
            ziti_close: ziti_sdk_c_close,
            ziti_write: ziti_sdk_c_write)
        self.tnlr_ctx = ziti_tunneler_init(&tunneler_opts, self.loop)
        
        let rStatus = uv_run(loop, UV_RUN_DEFAULT)
        guard rStatus == 0 else {
            let errStr = String(cString: uv_strerror(rStatus))
            NSLog("error running uv loop: \(rStatus) \(errStr)")
            return
        }
        NSLog("runZiti - loop exited with status 0")
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Logger.initShared(Logger.TUN_TAG)
        NSLog(versionString)
        
        //setenv("ZITI_LOG", "100", 1)
        //setenv("MBEDTLS_DEBUG", "4", 1)
        
        NSLog("startTunnel: options=\(options?.debugDescription ?? "nil")")
                
        //loop = uv_default_loop()
        loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        loop.initialize(to: uv_loop_t())
        let lstat = uv_loop_init(loop)
        
        guard lstat == 0 else {
            completionHandler(ZitiError("Unable to init uv_loop"))
            return
        }
        
        let conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as ProviderConfigDict
        if let error = self.providerConfig.parseDictionary(conf) {
            NSLog("Unable to startTunnel. Invalid providerConfiguration. \(error)")
            completionHandler(error)
            return
        }
        NSLog("\(self.providerConfig.debugDescription)")
        
        // load identities
        // for each svc aither update intercepts or add hostname to resolver
        if let idLoadErr = loadIdentites(loop) {
            completionHandler(idLoadErr)
            return
        }
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
        dnsSettings.matchDomains = [""] //self.providerConfig.dnsMatchDomains
 
        //print("----- matches: \(dnsSettings.matchDomains ?? [""])")
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
            
            // spawn thread running uv_loop
            Thread(target: self, selector: #selector(self.runZiti), object: nil).start()
            
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
