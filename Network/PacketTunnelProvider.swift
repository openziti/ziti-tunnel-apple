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

class PacketTunnelProvider: NEPacketTunnelProvider, ZitiTunnelProvider {
    let providerConfig = ProviderConfig()
    var appLogLevel:ZitiLog.LogLevel?
    var dnsResolver:DNSResolver?
    var interceptedRoutes:[NEIPv4Route] = []
    let netMon = NWPathMonitor()
    var currPath:Network.NWPath?
    var ifname:String?
    var zids:[ZitiIdentity] = []
    var allZitis:[Ziti] = [] // for ziti.dump...
    var zitiTunnel:ZitiTunnel!
    var loop:Ziti.ZitiRunloop!
    var writeLock = NSLock()
    var ipcServer:IpcAppexServer?
    
    var hasStarted = false // when true, restart is required to update routes for services intercepted by IP
    var startedAt:Date?
    var startupLock = NSLock()
    
    override init() {
        super.init()
        
        Logger.initShared(Logger.TUN_TAG)
        zLog.debug("")
        zLog.info(versionString)
        
        CZiti.Ziti.setAppInfo(Bundle.main.bundleIdentifier ?? "Ziti", Version.str)
        
        netMon.pathUpdateHandler = self.pathUpdateHandler
        netMon.start(queue: DispatchQueue.global())
        dnsResolver = DNSResolver()
        
        ipcServer = IpcAppexServer(self)
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
                        self.zitiTunnel.queuePacket(packet.data)
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
    
    func addRoute(_ destinationAddress: String) -> Int32 {
        var dest = destinationAddress
        var prefix:UInt32 = 32
        
        let parts = dest.components(separatedBy: "/")
        guard (parts.count == 1 || parts.count == 2) && IPUtils.isValidIpV4Address(parts[0]) else {
            // TODO: log
            return -1
        }
        if parts.count == 2, let prefixPart = UInt32(parts[1]) {
            dest = parts[0]
            prefix = prefixPart
        }
        let mask:UInt32 = (0xffffffff << (32 - prefix)) & 0xffffffff
        let subnetMask = "\(String((mask & 0xff000000) >> 24)).\(String((mask & 0x00ff0000) >> 16)).\(String((mask & 0x0000ff00) >> 8)).\(String(mask & 0x000000ff))"
        
        zLog.info("addRoute \(dest) => \(dest), \(subnetMask)")
        let route = NEIPv4Route(destinationAddress: dest,
                                subnetMask: subnetMask)
        
        // only add if haven't already.. (potential race condition now on interceptedRoutes...)
        var alreadyExists = true
        if interceptedRoutes.first(where: {
                                    $0.destinationAddress == route.destinationAddress &&
                                    $0.destinationSubnetMask == route.destinationSubnetMask}) == nil {
            alreadyExists = false
            interceptedRoutes.append(route)
        }
        
        startupLock.lock()
        if hasStarted && !alreadyExists {
            zLog.warn("*** Unable to add route for \(dest) to running tunnel. " +
                    "If route not already available it must be manually added (/sbin/route) or tunnel re-started ***")
            //svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: false) //true
            
        } else {
            zLog.info("Adding route for \(dest).")
            //svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available, needsRestart: false)
        }
        startupLock.unlock()
        return 0
    }
    
    func deleteRoute(_ dest: String) -> Int32 {
        zLog.warn("*** Unable to remove route for \(dest) on running tunnel. " +
                "If route not already available it must be manually removed (/sbin/route) or tunnel re-started ***")
        //svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: false) //true
        return 0
    }
    
    func fallbackDns(_ name: String) -> String? {
        //zLog.warn("Fallback DNS called unexpectedly...")
        return dnsResolver?.resolveHostname(name)
    }
    
    override var debugDescription: String {
        return "PacketTunnelProvider \(self)\n\(self.providerConfig)"
    }
    
    private func handleContextEvent(_ ziti:Ziti, _ zid:ZitiIdentity, _ zidStore:ZitiIdentityStore, _ zEvent:ZitiEvent) {
        guard let event = zEvent.contextEvent else {
            zLog.wtf("invalid event")
            return
        }
        
        let (cvers, _, _) = ziti.getControllerVersion()
        let cVersion = "\(cvers)"
        if zid.controllerVersion != cVersion {
            zid.controllerVersion = cVersion
        }
        
        if event.status == Ziti.ZITI_OK {
            zLog.info("\(zid.name):(\(zid.id)) \(zEvent.debugDescription)")
            zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
        } else {
            zLog.error("\(zid.name):(\(zid.id)) \(zEvent.debugDescription)")
            zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .PartiallyAvailable)
        }
        _ = zidStore.store(zid)
    }
    
    private func handleRouterEvent(_ ziti:Ziti, _ zid:ZitiIdentity, _ zidStore:ZitiIdentityStore, _ zEvent:ZitiEvent) {
        guard let _ = zEvent.routerEvent else {
            zLog.wtf("invalid event")
            return
        }
        zLog.info("\(zid.name):(\(zid.id)) \(zEvent.debugDescription)")
    }
    
    private func canDial(_ eSvc:CZiti.ZitiService) -> Bool {
        return (Int(eSvc.permFlags ?? 0x0) & Ziti.ZITI_CAN_DIAL != 0) && (eSvc.interceptConfigV1 != nil || eSvc.tunnelClientConfigV1 != nil)
    }
    
    private func processService(_ zid:ZitiIdentity, _ ztx:OpaquePointer, _ eSvc:CZiti.ZitiService, remove:Bool=false, add:Bool=false) {
        guard let cService = eSvc.cServicePtr, let serviceId = eSvc.id else {
            zLog.error("invalid service for \(zid.name):(\(zid.id)), name=\(eSvc.name ?? "nil"), id=\(eSvc.id ?? "nil")")
            return
        }
        
        if remove {
            self.dnsResolver?.removeDnsEntry(serviceId)
            self.zitiTunnel.onService(ztx, cService, Int32(Ziti.ZITI_SERVICE_UNAVAILABLE)) // cService.pointee, ZITI_SERVICE_UNAVAILABLE
            zid.services = zid.services.filter { $0.id != serviceId }
        }
        
        if add {
            let zSvc = ZitiService(eSvc)
            zSvc.addresses?.components(separatedBy: ",").forEach { addr in
                if !IPUtils.isValidIpV4Address(addr) {
                    dnsResolver?.addDnsEntry(addr, "", serviceId)
                }
            }
            if canDial(eSvc) {
                var needsRestart = false

                startupLock.lock()
                if let startedAt = self.startedAt, abs(startedAt.timeIntervalSinceNow) > 30.0 {
                    needsRestart = true
                }
                startupLock.unlock()
                
                if needsRestart {
                    zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: true)
                } else {
                    zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available, needsRestart: false)
                }
                
                zid.services.append(zSvc)
            }
            self.zitiTunnel.onService(ztx, cService, Int32(Ziti.ZITI_OK)) // &cService.pointee, ZITI_OK)
        }
    }
    
    private func handleServiceEvent(_ ziti:Ziti, _ zid:ZitiIdentity, _ zidStore:ZitiIdentityStore, _ zEvent:ZitiEvent) {
        guard let event = zEvent.serviceEvent, let ztx = ziti.ztx else {
            zLog.wtf("invalid event")
            return
        }
        
        if event.removed.count > 0 || event.changed.count > 0 || event.added.count > 0 {
            zLog.info("\(zid.name):(\(zid.id)) \(zEvent.debugDescription)")
        }
        
        for eSvc in event.removed { processService(zid, ztx, eSvc, remove:true) }
        for eSvc in event.changed { processService(zid, ztx, eSvc, remove:true, add:true) }
        for eSvc in event.added   { processService(zid, ztx, eSvc, add:true) }

        // Update controller status to .Available
        zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
        _ = zidStore.store(zid)
    }
    
    private func registerEventHandler(_ ziti:Ziti, _ zid:ZitiIdentity, _ zidStore:ZitiIdentityStore, _ gotServices: @escaping () ->Void) {
        ziti.registerEventCallback { zEvent in
            guard let zEvent = zEvent else {
                zLog.wtf("invald event")
                return
            }
            
            switch zEvent.type {
            case .Context: self.handleContextEvent(ziti, zid, zidStore, zEvent)
            case .Router:  self.handleRouterEvent(ziti, zid, zidStore, zEvent)
            case .Service:
                gotServices() // hack to wait for services to be reported to allow us to add intercept-by-ip routes
                self.handleServiceEvent(ziti, zid, zidStore, zEvent)
            case .MfaAuth:
                self.ipcServer?.queueMsg(IpcMfaAuthQueryMessage(zid.id, zEvent.mfaAuthEvent?.mfaAuthQuery))
            case .Invalid: zLog.error("Invalid event")
            @unknown default: zLog.error("unrecognized event type \(zEvent.type.debug)")
            }
        }
    }
    
    func dumpZitis() -> String {
        var str = ""
        let cond = NSCondition()
        var count = allZitis.count
        
        allZitis.forEach { z in
            z.perform {
                z.dump { str += $0; return 0 }
                //zLog.info(str)
                cond.lock()
                count -= 1
                cond.signal()
                cond.unlock()
            }
        }
        
        cond.lock()
        while (count > 0) {
            if !cond.wait(until: Date(timeIntervalSinceNow: TimeInterval(10.0))) {
                zLog.warn("Timed out waiting for logs == 0 (stuck at \(count))")
                break
            }
        }
        cond.unlock()
        return str
    }
    
    private func loadIdentites(_ loop:Ziti.ZitiRunloop) -> ZitiError? {
        
        let zidStore = ZitiIdentityStore()
        let (zids, zErr) = zidStore.loadAll()
        guard zErr == nil, zids != nil else { return zErr }
        
        let zidsLoadedCond = NSCondition() // so we can block waiting for services to be reported..
        var zidsToLoad = zids!.filter { $0.czid != nil && $0.isEnabled }.count
        
        let postureChecks = ZitiPostureChecks()
        let correctLogLevel = ZitiLog.getLogLevel() // first init of C SDK Ziti resets log level to INFO.  need to track that down, but for now...
        for zid in zids! {
            if let czid = zid.czid, zid.isEnabled == true {
                
                // blank out services before registering to hear back what they are..
                zid.services = []
                
                let ziti = Ziti(zid: czid, loopPtr: loop)
                allZitis.append(ziti)
                zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                _ = zidStore.store(zid)
                
                // Holds a reference to ziti object.
                // gotServices check used to attempt to delay until we have services so we can setup routes...
                var gotServices = false
                self.registerEventHandler(ziti, zid, zidStore) {
                    if !gotServices {
                        gotServices = true
                        ziti.perform {
                            zidsLoadedCond.lock()
                            zidsToLoad -= 1
                            zidsLoadedCond.signal()
                            zidsLoadedCond.unlock()
                        }
                    }
                }
                
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
                        zidsLoadedCond.lock()
                        zidsToLoad -= 1
                        zidsLoadedCond.signal()
                        zidsLoadedCond.unlock()
                        
                        return
                    }
                }
            }
        }
        self.zids = zids ?? []
        
        // spawn thread running uv_loop
        Thread(target: self, selector: #selector(self.runZiti), object: nil).start()
        
        // wait for services to be reported...
        zidsLoadedCond.lock()
        while zidsToLoad > 0 {
            if !zidsLoadedCond.wait(until: Date(timeIntervalSinceNow: TimeInterval(20.0))) {
                zLog.warn("Timed out waiting for zidToLoad == 0 (stuck at \(zidsToLoad))")
                break
            }
        }
        zidsLoadedCond.unlock()
                
        startupLock.lock()
        hasStarted = true
        self.startedAt = Date()
        startupLock.unlock()
        
        // Debug dump of DNS...
        // dnsResolver?.dumpDns()
        
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
        Ziti.executeRunloop(loopPtr: loop)
    }
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // call async so we can handle IPC calls while tunnel is starting up
        DispatchQueue.global().async {
            self.startTunnelAsync(options: options, completionHandler: completionHandler)
        }
    }

    func startTunnelAsync(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
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
            zLog.info("Setting log level to \(lvl)")
            ZitiLog.setLogLevel(lvl)
        }
                
        loop = CZiti.Ziti.ZitiRunloop()
        
        // setup ZitiTunnel
        let ipDNS = self.providerConfig.dnsAddresses.first ?? ""
        zitiTunnel = ZitiTunnel(self, loop, providerConfig.ipAddress, providerConfig.subnetMask, ipDNS)
        
        // load identities
        // for each svc aither update intercepts or add hostname to resolver
        if let idLoadErr = loadIdentites(loop) {
            completionHandler(idLoadErr)
            return
        }
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
        
        #if true // intercept_by_match_domains
            // Add in all the hostnames we want to intercept as 'matchDomains'. We'll get some extras, but that's ok, we'll proxy 'em...
            var matchDomains = self.dnsResolver?.hostnames
            
            // Make sure we don't become primary resolver (specified by having name = "")
            matchDomains = matchDomains?.filter { $0 != "" }
            if matchDomains == nil {
                matchDomains = [ "ziti-test.netfoundry.io" ]
            }
            dnsSettings.matchDomains = matchDomains
        #else
            // intercept and proxy all...
            dnsSettings.matchDomains = [""] //self.providerConfig.dnsMatchDomains
        #endif
        
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
        let dumpStr = dumpZitis()
        zLog.info(dumpStr)
        completionHandler()
        // Just exit - there are bugs in Apple macOS, plus makes sure we're 'clean' on restart
        zLog.info("")
        exit(EXIT_SUCCESS)
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let ipcServer = self.ipcServer else {
            zLog.wtf("Invalid/unitialized ipcServer")
            return
        }
        ipcServer.processMessage(messageData, completionHandler: completionHandler)
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
}
