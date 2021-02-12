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
    var currDnsServiceId:String?
    var interceptedRoutes:[NEIPv4Route] = []
    let netMon = NWPathMonitor()
    var currPath:Network.NWPath?
    var ifname:String?
    var zids:[ZitiIdentity] = []    
    var zitiTunnel:ZitiTunnel!
    var loop:UnsafeMutablePointer<uv_loop_t>!
    var writeLock = NSLock()
    
    var routesLocked = false // when true, restart is required to update routes for services intercepted by IP
    var rlLock = NSLock()
    
    override init() {
        super.init()
        
        Logger.initShared(Logger.TUN_TAG)
        zLog.debug("")
        zLog.info(versionString)
        
        CZiti.Ziti.setAppInfo(Bundle.main.bundleIdentifier ?? "Ziti", Version.str)
        
        netMon.pathUpdateHandler = self.pathUpdateHandler
        netMon.start(queue: DispatchQueue.global())
        dnsResolver = DNSResolver(self)
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
                        self.zitiTunnel.queuePacket(packet.data)
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
    
    func addRoute(_ dest: String) -> Int32 {
        let route = NEIPv4Route(destinationAddress: dest,
                                subnetMask: "255.255.255.255")
        
        // only add if haven't already.. (potential race condition now on interceptedRoutes...)
        var alreadyExists = true
        if interceptedRoutes.first(where: { $0.destinationAddress == route.destinationAddress }) == nil {
            alreadyExists = false
            interceptedRoutes.append(route)
        }
        
        // TODO: lookup service by currDnsServiceId and update
        //svc.dns?.interceptIp = "\(hn)"
        
        rlLock.lock()
        if routesLocked && !alreadyExists {
            zLog.warn("*** Unable to add route for \(dest) to running tunnel. " +
                    "If route not already available it must be manually added (/sbin/route) or tunnel re-started ***")
            //svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: false) //true
            
        } else {
            zLog.info("Adding route for \(dest).")
            //svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available, needsRestart: false)
        }
        rlLock.unlock()
        return 0
    }
    
    func deleteRoute(_ dest: String) -> Int32 {
        zLog.warn("*** Unable to remove route for \(dest) on running tunnel. " +
                "If route not already available it must be manually removed (/sbin/route) or tunnel re-started ***")
        //svc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: false) //true
        return 0
    }
    
    func applyDns(_ host: String, _ ip: String) -> Int32 {
        zLog.debug("Apply DNS: \(host) -> \(ip)")
        
        // horrible hack for getting the service id.  works because all happens in contenxt of libuv loop...
        dnsResolver?.addDnsEntry(host, ip, currDnsServiceId ?? "-1")
        return 0
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
        
        if event.status == ZITI_OK {
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
        return (UInt32(eSvc.permFlags ?? 0x0) & ZITI_CAN_DIAL != 0) && (eSvc.interceptConfigV1 != nil || eSvc.tunnelClientConfigV1 != nil)
    }
    
    private func handleServiceEvent(_ ziti:Ziti, _ zid:ZitiIdentity, _ zidStore:ZitiIdentityStore, _ zEvent:ZitiEvent) {
        guard let event = zEvent.serviceEvent else {
            zLog.wtf("invalid event")
            return
        }
        guard let ztx = ziti.ztx else {
            zLog.wtf("invalid ziti context")
            return
        }
        
        if event.removed.count > 0 || event.changed.count > 0 || event.added.count > 0 {
            zLog.info("\(zid.name):(\(zid.id)) \(zEvent.debugDescription)")
        }
        
        // REMOVE
        for eSvc in event.removed {
            guard let cService = eSvc.cService, let serviceId = eSvc.id else {
                zLog.error("invalid service for \(zid.name):(\(zid.id)), name=\(eSvc.name ?? "nil"), id=\(eSvc.id ?? "nil")")
                continue
            }
            self.dnsResolver?.removeDnsEntry(serviceId)
            self.zitiTunnel.onService(ztx, &cService.pointee, ZITI_SERVICE_UNAVAILABLE)
            zid.services = zid.services.filter { $0.id != serviceId }
        }
        
        // CHANGE
        for eSvc in event.changed {
            guard let cService = eSvc.cService, let serviceId = eSvc.id else {
                zLog.error("invalid service for \(zid.name):(\(zid.id)), name=\(eSvc.name ?? "nil"), id=\(eSvc.id ?? "nil")")
                continue
            }
           
            // Remove it
            self.dnsResolver?.removeDnsEntry(serviceId)
            self.zitiTunnel.onService(ztx, &cService.pointee, ZITI_SERVICE_UNAVAILABLE)
            zid.services = zid.services.filter { $0.id != serviceId }
            
            // Add it back
            self.currDnsServiceId = serviceId
            if canDial(eSvc) { zid.services.append(ZitiService(eSvc)) }
            self.zitiTunnel.onService(ztx, &cService.pointee, ZITI_OK)
        }
        
        // ADD
        for eSvc in event.added {
            guard let cService = eSvc.cService else {
                zLog.error("invalid service for \(zid.name):(\(zid.id)), name=\(eSvc.name ?? "nil"), id=\(eSvc.id ?? "nil")")
                continue
            }
            
            self.currDnsServiceId = eSvc.id
            if canDial(eSvc) { zid.services.append(ZitiService(eSvc)) }
            self.zitiTunnel.onService(ztx, &cService.pointee, ZITI_OK)
        }

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
            case .Invalid: zLog.error("Invalid event")
            @unknown default: zLog.error("unrecognized event type \(zEvent.type.debug)")
            }
        }
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
                
                // Holds a reference to ziti object.
                // gotServices check used to attempt to delay until we have services so we can setup routes...
                var gotServices = false
                self.registerEventHandler(ziti, zid, zidStore) {
                    if !gotServices {
                        gotServices = true
                        ziti.perform {
                            routeCond.lock()
                            zidsToLoad -= 1
                            routeCond.signal()
                            routeCond.unlock()
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
                        routeCond.lock()
                        zidsToLoad -= 1
                        routeCond.signal()
                        routeCond.unlock()
                        
                        return
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
            if !routeCond.wait(until: Date(timeIntervalSinceNow: TimeInterval(20.0))) {
                zLog.warn("Timed out waiting for zidToLoad == 0 (stuck at \(zidsToLoad))")
                break
            }
        }
        routeCond.unlock()
                
        rlLock.lock()
        routesLocked = true
        rlLock.unlock()
        
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
            zLog.info("Setting log level to \(lvl)")
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
        
        // setup ZitiTunnel
        zitiTunnel = ZitiTunnel(self, loop, providerConfig.ipAddress, providerConfig.subnetMask)
        
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
