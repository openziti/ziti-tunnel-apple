//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import NetworkExtension
import Network
import CZiti

class ZitiTunnelClientConfig : Codable {
    static var configType = "ziti-tunneler-client.v1"
    
    let hostname:String
    let port:Int
    
    static func parseConfig(_ zs: inout ziti_service) -> ZitiTunnelClientConfig? {
        if let cfg = ziti_service_get_raw_config(&zs, ZitiTunnelClientConfig.configType.cString(using: .utf8)) {
            return try? JSONDecoder().decode(ZitiTunnelClientConfig.self, from: Data(String(cString: cfg).utf8))
        }
        return nil
    }
}

class ZitiTunnelServerConfig : Codable {
    static var configType = "ziti-tunneler-server.v1"
    enum CodingKeys: String, CodingKey {
            case hostname
        
            case port
            case proto = "protocol"
        }
    
    let hostname:String
    let port:Int
    let proto:String // `protocol` is a reserved word...
    
    static func parseConfig(_ zs: inout ziti_service) -> ZitiTunnelServerConfig? {
        if let cfg = ziti_service_get_raw_config(&zs, ZitiTunnelServerConfig.configType.cString(using: .utf8)) {
            return try? JSONDecoder().decode(ZitiTunnelServerConfig.self, from: Data(String(cString: cfg).utf8))
        }
        return nil
    }
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    let providerConfig = ProviderConfig()
    var appLogLevel:ZitiLog.LogLevel?
    var dnsResolver:DNSResolver?
    var interceptedRoutes:[NEIPv4Route] = []
    let netMon = NWPathMonitor()
    var currPath:Network.NWPath?
    var ifname:String?
    var zids:[ZitiIdentity] = []    
    var netifDriver:NetifDriver!
    var tnlr_ctx:tunneler_context?
    var loop:UnsafeMutablePointer<uv_loop_t>!
    var writeLock = NSLock()
    
    var routesLocked = false // when true, restart is required to update routes for services intercepted by IP
    var rlLock = NSLock()
    
    override init() {
        super.init()
        
        Logger.initShared(Logger.TUN_TAG)
        zLog.debug("")
        zLog.info(versionString)
        
        netMon.pathUpdateHandler = self.pathUpdateHandler
        netMon.start(queue: DispatchQueue.global())
        dnsResolver = DNSResolver(self)
        netifDriver = NetifDriver(ptp: self)
    }
    
    func pathUpdateHandler(path: Network.NWPath) {
        currPath = path
        var ifaceStr = ""
        for i in path.availableInterfaces {
            ifaceStr += " \n     \(i.index): name:\(i.name), type:\(i.type)"
        }
        zLog.info("Network Path Update:\n   Status:\(path.status), Expensive:\(path.isExpensive), Cellular:\(path.usesInterfaceType(.cellular))\n   Interfaces:\(ifaceStr)")
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
                
                // only add if haven't already.. (potential race condition now on interceptedRoutes...)
                var alreadyExists = true
                if interceptedRoutes.first(where: { $0.destinationAddress == route.destinationAddress }) == nil {
                    alreadyExists = false
                    interceptedRoutes.append(route)
                }
                svc.dns?.interceptIp = "\(hn)"
                
                rlLock.lock()
                if routesLocked && !alreadyExists {
                    zLog.warn("*** Unable to add route for \(zid.name): \(hn) (port \(port)) to running tunnel. " +
                            "If route not already available it must be manually added (/sbin/route) or tunnel re-started ***")
                    svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: true)
                    
                } else {
                    zLog.info("Adding route for \(zid.name): \(hn) (port \(port)).")
                    svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available, needsRestart: false)
                }
                rlLock.unlock()
            } else {
                svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available)
                dnsResolver?.hostnamesLock.lock()
                // See if we already have this DNS name
                if let currIPs = dnsResolver?.findRecordsByName(hn), currIPs.count > 0 {
                    svc.dns?.interceptIp = "\(currIPs.first!.ip)"
                    zLog.info("Using DNS hostname \(hn): \(currIPs.first!.ip) (port \(port))")
                } else if let ipStr = dnsResolver?.addHostname(hn) {
                    svc.dns?.interceptIp = "\(ipStr)"
                    zLog.info("Adding DNS hostname \(hn): \(ipStr) (port \(port))")
                } else {
                    zLog.info("Unable to add DNS hostname \(hn) for \(zid.name)")
                    svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Unavailable, needsRestart: false)
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
        
        let routeCond = NSCondition() // so we can block waiting for services to be reported..
        var zidsToLoad = zids!.filter { $0.czid != nil && $0.isEnabled }.count
        
        let postureChecks = ZitiPostureChecks()
        let correctLogLevel = ZitiLog.getLogLevel() // first init of C SDK Ziti resets log level to INFO.  need to track that down, but for now...
        for zid in zids! {
            if let czid = zid.czid, zid.isEnabled == true {
                
                // blank out services before registering to hear back what they are..
                zid.services = []
                
                let ziti = Ziti(zid: czid, loop: loop)
                zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                _ = zidStore.store(zid)
                
                ziti.run(postureChecks) { zErr in
                    
                    // Blech. Track this down...
                    let currLogLevel = ZitiLog.getLogLevel()
                    if currLogLevel != correctLogLevel {
                        zLog.info("Correcting logLevel.  Was \(currLogLevel), updating to \(correctLogLevel)")
                        ZitiLog.setLogLevel(correctLogLevel)
                    }
                    
                    guard zErr == nil else {
                        zLog.error("Unable to init \(zid.name):\(zid.id), err: \(zErr!.localizedDescription)")
                        zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                        _ = zidStore.store(zid)
                        
                        // dec the count (otherwise will need to wait for condition to timeout
                        routeCond.lock()
                        zidsToLoad -= 1
                        routeCond.signal()
                        routeCond.unlock()
                        
                        return
                    }
                    zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
                    
                    let (cvers, _, _) = ziti.getControllerVersion()
                    let cVersion = "\(cvers)"
                    if zid.controllerVersion != cVersion {
                        zid.controllerVersion = cVersion
                    }
                     _ = zidStore.store(zid)
                    
                    // forces reference to ziti to be kept by ziti.  generally not a great idea, but fine
                    // for us since we want the ziti instance to exist for the entire run (new or deleted
                    // identities cause tunnel to be restarted). will need to change this to a weak reference
                    // to `ziti` if we change from restarting on add/delete of identities, and add management
                    // of `ziti` lifecycle...
                    var gotServices = false
                    ziti.registerServiceCallback { [weak self] ztx, zs, status in
                        
                        // C SDK currently grabs all services in single call.  Eventtually it'll be
                        // paginated, but for now, once C SDK reports on a single service it knows about
                        // all of 'em, and puts all the service callbacks on the loop. So if we've got
                        // any service for this zid, we've got them all
                        if !gotServices {
                            gotServices = true
                            ziti.perform {
                                routeCond.lock()
                                zidsToLoad -= 1
                                routeCond.signal()
                                routeCond.unlock()
                            }
                        }
                        
                        guard var zs = zs?.pointee, let self = self else { return }
                        
                        let serviceName = String(cString: zs.name)
                        let serviceId = String(cString: zs.id)
                        let serviceWas = zid.services.first(where: { $0.id == serviceId })
                        
                        if status == ZITI_OK && ((zs.perm_flags & Int32(ZITI_CAN_BIND)) != 0) {
                            zLog.debug("service \(serviceName) CAN bind")
                            if let cfg = ZitiTunnelServerConfig.parseConfig(&zs) {
                                zLog.debug("Bind config hostname:\(cfg.hostname), port:\(cfg.port), proto:\(cfg.proto)")
                                ziti_tunneler_host_v1(self.tnlr_ctx, UnsafeRawPointer(ztx), zs.name,
                                                      cfg.proto.cString(using: .utf8),
                                                      cfg.hostname.cString(using: .utf8),
                                                      Int32(cfg.port))
                            } else {
                                zLog.error("Unable to parse server config for \(serviceName)")
                            }
                        }
                        
                        if status == ZITI_OK && ((zs.perm_flags & Int32(ZITI_CAN_DIAL)) != 0) {
                            if let cfg = ZitiTunnelClientConfig.parseConfig(&zs) {
                                zLog.debug("Service Available \(zid.name)::\(serviceName)")
                                
                                if let svc = serviceWas {
                                    // Update all fields except interceptIP
                                    svc.name = serviceName
                                    
                                    // if dns changed we need to update DNS hostnames
                                    if svc.dns?.hostname != cfg.hostname {
                                        if self.countInterceptRefs(zids!, svc.dns?.interceptIp ?? "") == 1 {
                                            if let interceptIp = svc.dns?.interceptIp, let dnsResolver = self.dnsResolver {
                                                let hn = svc.dns?.hostname ?? ""
                                                zLog.debug("Removing DNS entry for service \(serviceName), \(hn) != \(interceptIp)")
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
                                        zLog.debug("Updating intercept for \(serviceName), \(cfg.hostname)->\(interceptIp)")
                                        ziti_tunneler_intercept_v1(self.tnlr_ctx, UnsafeRawPointer(ztx), zs.id, zs.name, interceptIp.cString(using: .utf8), Int32(cfg.port))
                                        svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available)
                                    }
                                    
                                } else {
                                    let newSvc = ZitiService()
                                    newSvc.name = serviceName
                                    newSvc.id = serviceId
                                    newSvc.dns = ZitiService.Dns()
                                    newSvc.dns?.hostname = cfg.hostname
                                    newSvc.dns?.port = cfg.port
                                    
                                    self.updateHostsAndIntercepts(zid, newSvc)
                                    if let interceptIp = newSvc.dns?.interceptIp {
                                        zLog.debug("Adding intercept for \(serviceName), \(cfg.hostname)->\(interceptIp)")
                                        ziti_tunneler_intercept_v1(self.tnlr_ctx, UnsafeRawPointer(ztx), zs.id, zs.name, interceptIp.cString(using: .utf8), Int32(cfg.port))
                                    }
                                    zid.services.append(newSvc)
                                }
                            } else {
                                zLog.error("Unable to parse config for serivce \(serviceName):\(serviceId)")
                            }
                        } else if status == ZITI_SERVICE_UNAVAILABLE {
                            zLog.debug("Service Unvailable \(zid.name)::\(serviceName)")
                            
                            let refCount = self.countInterceptRefs(zids!, serviceWas?.dns?.interceptIp ?? "")
                            if refCount == 1 {
                                // remove from hostnames (locked) TODO: move DNS stuff into DnsResolver
                                if let interceptIp = serviceWas?.dns?.interceptIp, let dnsResolver = self.dnsResolver {
                                    let hn = serviceWas?.dns?.hostname ?? ""
                                    zLog.debug("Removing DNS entry for service \(serviceName), \(hn) != \(interceptIp)")
                                    dnsResolver.hostnamesLock.lock()
                                    dnsResolver.hostnames = dnsResolver.hostnames.filter { $0.ip != interceptIp }
                                    dnsResolver.hostnamesLock.unlock()
                                }
                            } else {
                                zLog.debug("Leaving DNS entry, refCount was \(refCount)")
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
        
        // spawn thread running uv_loop
        Thread(target: self, selector: #selector(self.runZiti), object: nil).start()
        
        // wait for services to be reported...
        routeCond.lock()
        while zidsToLoad > 0 {
            if !routeCond.wait(until: Date(timeIntervalSinceNow: TimeInterval(15.0))) {
                zLog.warn("Timed out waiting for zidToLoad == 0 (stuck at \(zidsToLoad)")
                break
            }
        }
        routeCond.unlock()
                
        rlLock.lock()
        routesLocked = true
        rlLock.unlock()
        
        return nil
    }
    
    var versionString:String {
        get {
            let z = Ziti(withId: CZiti.ZitiIdentity(id: "", ztAPI: ""))
            let (vers, rev, buildDate) = z.getCSDKVersion()
            return "\(Version.verboseStr); ziti-sdk-c version \(vers)-\(rev)(\(buildDate))"
        }
    }
    
    @objc func runZiti() {
        // make sure we have netif setup before returning or starting run loop
        var tunneler_opts = tunneler_sdk_options(
            netif_driver: self.netifDriver.open(),
            ziti_dial: ziti_sdk_c_dial,
            ziti_close: ziti_sdk_c_close,
            ziti_write: ziti_sdk_c_write,
            ziti_host_v1: ziti_sdk_c_host_v1_wrapper)
        self.tnlr_ctx = ziti_tunneler_init(&tunneler_opts, self.loop)
        
        let rStatus = uv_run(loop, UV_RUN_DEFAULT)
        guard rStatus == 0 else {
            let errStr = String(cString: uv_strerror(rStatus))
            zLog.wtf("error running uv loop: \(rStatus) \(errStr)")
            return
        }
        zLog.info("runZiti - loop exited with status 0")
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        zLog.info("startTunnel: options=\(options?.debugDescription ?? "nil")")
        
        let conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as ProviderConfigDict
        if let error = self.providerConfig.parseDictionary(conf) {
            zLog.wtf("Unable to startTunnel. Invalid providerConfiguration. \(error)")
            completionHandler(error)
            return
        }
        zLog.info("\(self.providerConfig.debugDescription)")
        zLog.info("providerConfig.logLevel = \(providerConfig.logLevel)")
        
        if let appLogLevel = self.appLogLevel, appLogLevel.rawValue != Int32(providerConfig.logLevel) {
            zLog.info("Overriding providerConfig.logLevel to appLogLevel of \(appLogLevel)")
            ZitiLog.setLogLevel(appLogLevel)
        } else {
            let lvl = ZitiLog.LogLevel(rawValue: Int32(providerConfig.logLevel)) ?? ZitiLog.LogLevel.INFO
            zLog.info("Updating log level to \(lvl)")
            ZitiLog.setLogLevel(lvl)
        }
                
        //loop = uv_default_loop()
        loop = UnsafeMutablePointer<uv_loop_t>.allocate(capacity: 1)
        loop.initialize(to: uv_loop_t())
        let lstat = uv_loop_init(loop)
        guard lstat == 0 else {
            completionHandler(ZitiError("Unable to init uv_loop"))
            return
        }
        
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
            zLog.info("route: \(r.destinationAddress) / \(r.destinationSubnetMask)")
        }
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = interceptedRoutes
        // TODO: ipv6Settings
        tunnelNetworkSettings.mtu = self.providerConfig.mtu as NSNumber
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            if let error = error {
                zLog.error(error.localizedDescription)
                completionHandler(error as NSError)
            }

            // packetFlow FD
            let fd = (self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32) ?? -1
            if fd < 0 {
                zLog.warn("Unable to get tun fd")
            } else {
                var ifnameSz = socklen_t(IFNAMSIZ)
                let ifnamePtr = UnsafeMutablePointer<CChar>.allocate(capacity: Int(ifnameSz))
                ifnamePtr.initialize(repeating: 0, count: Int(ifnameSz))
                if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, ifnamePtr, &ifnameSz) == 0 {
                    self.ifname = String(cString: ifnamePtr)
                }
                ifnamePtr.deallocate()
            }
            zLog.info("Tunnel interface is \(self.ifname ?? "unknown")")
            
            // call completion handler with nil to indicate success
            completionHandler(nil)
            
            //
            // Start listening for traffic headed our way via the tun interface
            //
            self.readPacketFlow()
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        zLog.info("")
        completionHandler()
        // Just exit - there are bugs in Apple macOS, plus makes sure we're 'clean' on restart
        exit(EXIT_SUCCESS)
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let messageString = NSString(data: messageData, encoding: String.Encoding.utf8.rawValue) else {
            completionHandler?(nil)
            return
        }
        zLog.debug("PTP Got message from app... \(messageString)")
        let arr = messageString.components(separatedBy: "=")
        if arr.count == 2 && arr.first == "logLevel" {
            let lvlStr = arr.last ?? "3"
            let lvl:ZitiLog.LogLevel = ZitiLog.LogLevel(rawValue: Int32(lvlStr) ?? ZitiLog.LogLevel.INFO.rawValue) ?? ZitiLog.LogLevel.INFO
            zLog.info("Updating LogLevel to \(lvl)")
            ZitiLog.setLogLevel(lvl)
            
            // Can be a timing issue with App updating config and startTunnel().  If we get a logLevel here, cache it
            // in case startTunnel() is called after receiving this message...
            appLogLevel = lvl
        }
        
        completionHandler?(nil)
        /*if let handler = completionHandler {
            handler(messageData)
        }*/
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
}
