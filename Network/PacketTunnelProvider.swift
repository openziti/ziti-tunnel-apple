//
// Copyright NetFoundry, Inc.
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
import UserNotifications

class PacketTunnelProvider: NEPacketTunnelProvider, ZitiTunnelProvider, UNUserNotificationCenterDelegate {
    
    static let MFA_POSTURE_CHECK_TIMER_INTERVAL:UInt64 = 30
    static let MFA_POSTURE_CHECK_FIRST_NOTICE:UInt64 = 300
    static let MFA_POSTURE_CHECK_FINAL_NOTICE:UInt64 = 120
    
    let providerConfig = ProviderConfig()
    var appLogLevel:ZitiLog.LogLevel?
    var dnsEntries:DNSEntries = DNSEntries()
    var interceptedRoutes:[NEIPv4Route] = []
    var excludedRoutes:[NEIPv4Route] = []
    let netMon = NWPathMonitor()
    var allZitis:[Ziti] = [] // for ziti.dump...
    var zitiTunnel:ZitiTunnel?
    var writeLock = NSLock()
    var ipcServer:IpcAppexServer?
    let zidStore = ZitiIdentityStore()
    var tzids:[ZitiIdentity]?
    var identitiesLoaded = false // when true, restart is required to update routes for services intercepted by IP
    let userNotifications = UserNotifications.shared
    
    override init() {
        super.init()
        
        Logger.initShared(Logger.TUN_TAG)
        zLog.debug("")
        zLog.info(versionString)
        
        CZiti.Ziti.setAppInfo(Bundle.main.bundleIdentifier ?? "Ziti", Version.str)
        
        netMon.pathUpdateHandler = { path in
            var ifaceStr = ""
            for i in path.availableInterfaces {
                ifaceStr += " \n     \(i.index): name:\(i.name), type:\(i.type)"
            }
            zLog.info("Network Path Update:\nStatus:\(path.status), Expensive:\(path.isExpensive), Cellular:\(path.usesInterfaceType(.cellular))\n   Interfaces:\(ifaceStr)")
        }
        netMon.start(queue: DispatchQueue.global())
        
        ipcServer = IpcAppexServer(self)
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        userNotifications.requestAuth()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // On macOS, method is not reliably called. When it is, results are ignored (notification is not displayed)
        zLog.debug("willPresent: \(notification.debugDescription)")
        completionHandler([.list, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // This is only called on macOS.  On iOS, the app's AppDelegate gets notified...
        zLog.debug("didReceive: \(response.debugDescription)")
        if let zid = response.notification.request.content.userInfo["zid"] as? String, let tzid = zidToTzid(zid) {
            tzid.addAppexNotification(IpcAppexNotificationMessage(
                zid, response.notification.request.content.categoryIdentifier, response.actionIdentifier))
            _ = zidStore.store(tzid)
        } else if let zid = tzids?.first?.id, let tzid = zidToTzid(zid)   {
            tzid.addAppexNotification(IpcAppexNotificationMessage(
                nil, response.notification.request.content.categoryIdentifier, response.actionIdentifier))
            _ = zidStore.store(tzid)
        }
        completionHandler()
    }
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // call async so we can handle IPC calls while tunnel is starting up
        DispatchQueue.global().async {
            self.startTunnelAsync(options: options, completionHandler: completionHandler)
        }
    }

    func startTunnelAsync(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        zLog.info("")
        zLog.info("options=\(options?.debugDescription ?? "nil")")
        
        // parse config
        let conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as ProviderConfigDict
        if let error = self.providerConfig.parseDictionary(conf) {
            let errStr = "Unable to start tunnel. Invalid provider configuration. \(error)"
            zLog.wtf(errStr)
            userNotifications.post(.Error, nil, errStr)
            completionHandler(error)
            return
        }
        zLog.info("\(self.providerConfig.debugDescription)")
        zLog.info("providerConfig.logLevel = \(providerConfig.logLevel)")
        
        // setup logLevel
        if let appLogLevel = self.appLogLevel, appLogLevel.rawValue != Int32(providerConfig.logLevel) {
            zLog.info("Overriding providerConfig.logLevel to appLogLevel of \(appLogLevel)")
            ZitiLog.setLogLevel(appLogLevel)
        } else {
            let lvl = ZitiLog.LogLevel(rawValue: Int32(providerConfig.logLevel)) ?? ZitiLog.LogLevel.INFO
            zLog.info("Setting log level to \(lvl)")
            ZitiLog.setLogLevel(lvl)
        }
                        
        // setup ZitiTunnel
        let ipDNS = self.providerConfig.dnsAddresses.first ?? ""
        var upstreamDns:String?
        if providerConfig.fallbackDnsEnabled {
            upstreamDns = providerConfig.fallbackDns
        }
        
        // Current Ziti Tunneler SDK returns REFUSED for non-Ziti DNS requests, whcih there will be a ton of
        // when not intercepting by matchDomains.  REFUSED no longer works as expected on macOS (it used to
        // behave like most Linux systems and automatically resolver#2 to be queried, but now it causes the
        // query to fail), so we have to have a fallback.  Try to determing current first resolver
        // and use if for fallback. Otherwise pick a reasonable default.
        // TODO: on iOS, we find the first resolver, but setting any fallbackDNS is causing issues
        #if os(macOS)
        if upstreamDns == nil {
            let firstResolver = dnsEntries.getFirstResolver()
            zLog.warn("No fallback DNS provided. Setting to first resolver: \(firstResolver as Any)")
            upstreamDns = firstResolver
        }
        
        if upstreamDns == nil {
            zLog.warn("No fallback DNS available. Defaulting to 1.1.1.1")
            upstreamDns = "1.1.1.1"
        }
        #endif
        
        zitiTunnel = ZitiTunnel(self, providerConfig.ipAddress, providerConfig.subnetMask, ipDNS, upstreamDns)
        
        // read in the .zid files
        let (tzids, zErr) = zidStore.loadAll()
        guard zErr == nil, let tzids = tzids else {
            let errStr = "Unable load identities. \(zErr != nil ? zErr!.localizedDescription : "")"
            zLog.error(errStr)
            userNotifications.post(.Error, nil, errStr)
            completionHandler(zErr ?? ZitiError("Unable to load .zid files"))
            return
        }
        self.tzids = tzids
                
        // create list of CZiti.ZitiIdenty type used by CZiti.ZitiTunnel
        var zids:[CZiti.ZitiIdentity] = []
        tzids.forEach { tzid in
            if let czid = tzid.czid, tzid.isEnabled == true {
                tzid.appexNotifications = nil
                tzid.services = []
                tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                _ = zidStore.store(tzid)
                zids.append(czid)
            }
        }
        
        // start 'er up
        zitiTunnel?.startZiti(zids, ZitiPostureChecks()) { zErr in
            guard zErr == nil else {
                zLog.error("Unable to load identites: \(zErr!.localizedDescription)")
                self.userNotifications.post(.Error, nil, "Unable to start Ziti: \(zErr!.localizedDescription)")
                completionHandler(zErr)
                return
            }
            self.identitiesLoaded = true
            
            // notifiy Ziti on unlock
            #if os(macOS)
                DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"), object:nil, queue: OperationQueue.main) { _ in
                    zLog.debug("---screen unlock----")
                    self.allZitis.forEach { $0.endpointStateChange(false, true) }
                }
            
            
                // set timer to check pending MFA posture timeouts
                self.allZitis.first?.startTimer(
                    PacketTunnelProvider.MFA_POSTURE_CHECK_TIMER_INTERVAL * 1000,
                    PacketTunnelProvider.MFA_POSTURE_CHECK_TIMER_INTERVAL * 1000) { _ in
                    self.onMfaPostureTimer()
                }
            #endif
            
            // identies have loaded, so go ahead and setup the TUN
            let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
            let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
            
            if self.providerConfig.interceptMatchedDns {
                // Add in all the hostnames we want to intercept as 'matchDomains'. We might get some extras, but that's ok...
                var matchDomains = self.dnsEntries.hostnames.map { // trim of "*." for wildcard domains
                    $0.starts(with: "*.") ? String($0.dropFirst(2)) : $0 // shaky. come back to this
                }
                
                // Make sure we don't become primary resolver (specified by having name = "")
                matchDomains = matchDomains.filter { $0 != "" }
                if matchDomains.count == 0 {
                    matchDomains = [ "ziti-test.netfoundry.io" ]
                }
                dnsSettings.matchDomains = matchDomains
            } else {
                // intercept and proxy all to upstream DNS (if set, else rejects)
                dnsSettings.matchDomains = [""]
            }
            tunnelNetworkSettings.dnsSettings = dnsSettings
            
            // add dnsServer routes if configured outside of configured subnet
            let net = IPUtils.ipV4AddressStringToData(self.providerConfig.ipAddress)
            let mask = IPUtils.ipV4AddressStringToData(self.providerConfig.subnetMask)
            dnsSettings.servers.forEach { svr in
                let dest = IPUtils.ipV4AddressStringToData(svr)
                if IPUtils.inV4Subnet(dest, network: net, mask: mask) == false {
                    self.interceptedRoutes.append(NEIPv4Route(destinationAddress: svr, subnetMask: "255.255.255.255"))
                }
            }
            
            tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [self.providerConfig.ipAddress],
                                                                subnetMasks: [self.providerConfig.subnetMask])
            let includedRoute = NEIPv4Route(destinationAddress: self.providerConfig.ipAddress,
                                            subnetMask: self.providerConfig.subnetMask)
            self.interceptedRoutes.append(includedRoute)
            self.interceptedRoutes.forEach { r in
                zLog.info("route: \(r.destinationAddress) / \(r.destinationSubnetMask)")
            }
            self.excludedRoutes.forEach { r in
                zLog.info("excluding route: \(r.destinationAddress) / \(r.destinationSubnetMask)")
            }
            tunnelNetworkSettings.ipv4Settings?.includedRoutes = self.interceptedRoutes
            tunnelNetworkSettings.ipv4Settings?.excludedRoutes = self.excludedRoutes
            tunnelNetworkSettings.mtu = self.providerConfig.mtu as NSNumber
            
            self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
                if let error = error {
                    zLog.error(error.localizedDescription)
                    completionHandler(error as NSError)
                }
                
                // interferes with any notifications posted while connecting...
                //self.userNotifications.post(.Info, "Connected")

                // call completion handler with nil to indicate success
                completionHandler(nil)
                
                // Start listening for traffic headed our way via the tun interface
                self.readPacketFlow()
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let dumpStr = dumpZitis()
        zLog.info(dumpStr)
        
        guard let zitiTunnel = zitiTunnel else {
            userNotifications.post(.Info, "Disconnected", nil, nil) {
                zLog.error("No valid zitiTunnel context found. Exiting.")
                completionHandler()
                exit(EXIT_SUCCESS)
            }
            return
        }
        
        zitiTunnel.shutdownZiti {
            self.userNotifications.post(.Info, "Disconnected", nil, nil) {
                zLog.info("Exiting")
                completionHandler()
               // exit(EXIT_SUCCESS)
            }
        }
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        zLog.debug("")
        guard let ipcServer = self.ipcServer else {
            zLog.wtf("Invalid/unitialized ipcServer")
            return
        }
        ipcServer.processMessage(messageData, completionHandler: completionHandler)
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        //zLog.debug("---Sleep---")
        completionHandler()
    }
    
    override func wake() {
        zLog.debug("---Wake---")
        allZitis.forEach { $0.endpointStateChange(true, false) }
    }
    
    func readPacketFlow() {
        packetFlow.readPacketObjects { (packets:[NEPacket]) in
            for packet in packets {
                if packet.data.count > 0 {
                    self.zitiTunnel?.queuePacket(packet.data)
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
    
    func onMfaPostureTimer() {
        guard let tzids = tzids else { return }
        
        let now = Date()
        let firstNoticeMin = PacketTunnelProvider.MFA_POSTURE_CHECK_FIRST_NOTICE - PacketTunnelProvider.MFA_POSTURE_CHECK_TIMER_INTERVAL
        let finalNoticeMin = PacketTunnelProvider.MFA_POSTURE_CHECK_FINAL_NOTICE - PacketTunnelProvider.MFA_POSTURE_CHECK_TIMER_INTERVAL
        
        let zidMgr = ZidMgr()
        for tzid in tzids {
            
            // if already failing posture checks don't bother (user notification was already sent)
            if !tzid.isEnabled || !tzid.isEnrolled || !zidMgr.allServicePostureChecksPassing(tzid) {
                continue
            }
            
            // find the lowest MFA timeout set for this identity (if any)
            var lowestTimeRemaining:Int32 = Int32.max
            tzid.services.forEach { svc in
                svc.postureQuerySets?.forEach{ pqs in
                    if pqs.isPassing ?? true {
                        pqs.postureQueries?.forEach{ pq in
                            if let qt = pq.queryType, qt == "MFA", let tr = pq.timeoutRemaining, tr > 0, let lua = svc.status?.lastUpdatedAt {
                                let lastUpdatedAt = Date(timeIntervalSince1970: lua)
                                let timeSinceLastUpdate = Int32(now.timeIntervalSince(lastUpdatedAt))
                                let actualTimeRemaining = tr - timeSinceLastUpdate
                                if actualTimeRemaining < lowestTimeRemaining {
                                    lowestTimeRemaining = actualTimeRemaining
                                }
                            }
                        }
                    }
                }
            }
            
            // Notify user...
            if lowestTimeRemaining > firstNoticeMin && lowestTimeRemaining < PacketTunnelProvider.MFA_POSTURE_CHECK_FIRST_NOTICE {
                zLog.info("\(tzid.name) MFA expiring in less then \(PacketTunnelProvider.MFA_POSTURE_CHECK_FIRST_NOTICE) secs \(lowestTimeRemaining)")
                self.userNotifications.post(.Mfa, "MFA Auth Posture Check",
                                            "\(tzid.name) MFA expiring in less then \(UInt64(PacketTunnelProvider.MFA_POSTURE_CHECK_FIRST_NOTICE/60)) mins",
                                            tzid)
            } else if lowestTimeRemaining > finalNoticeMin && lowestTimeRemaining < PacketTunnelProvider.MFA_POSTURE_CHECK_FINAL_NOTICE {
                self.userNotifications.post(.Mfa, "MFA Auth Posture Check",
                                            "\(tzid.name) MFA expiring in less then \(PacketTunnelProvider.MFA_POSTURE_CHECK_FIRST_NOTICE) secs",
                                            tzid)
            }
        }
    }
     
    func cidrToDestAndMask(_ cidr:String) -> (String?, String?) {
        var dest = cidr
        var prefix:UInt32 = 32
        
        let parts = dest.components(separatedBy: "/")
        guard (parts.count == 1 || parts.count == 2) && IPUtils.isValidIpV4Address(parts[0]) else {
            return (nil, nil)
        }
        if parts.count == 2, let prefixPart = UInt32(parts[1]) {
            dest = parts[0]
            prefix = prefixPart
        }
        let mask:UInt32 = (0xffffffff << (32 - prefix)) & 0xffffffff
        let subnetMask = "\(String((mask & 0xff000000) >> 24)).\(String((mask & 0x00ff0000) >> 16)).\(String((mask & 0x0000ff00) >> 8)).\(String(mask & 0x000000ff))"
        return (dest, subnetMask)
    }
    
    func addRoute(_ destinationAddress: String) -> Int32 {
        let (dest, subnetMask) = cidrToDestAndMask(destinationAddress)
        
        if let dest = dest, let subnetMask = subnetMask {
            
            zLog.info("addRoute \(dest) => \(dest), \(subnetMask)")
            let route = NEIPv4Route(destinationAddress: dest,
                                    subnetMask: subnetMask)
            
            // only add if haven't already..
            var alreadyExists = true
            if interceptedRoutes.first(where: {
                                        $0.destinationAddress == route.destinationAddress &&
                                        $0.destinationSubnetMask == route.destinationSubnetMask}) == nil {
                alreadyExists = false
            }
            
            if !alreadyExists {
                if identitiesLoaded {
                    zLog.warn("*** Unable to add route for \(destinationAddress) to running tunnel. " +
                            "If route not already available it must be manually added (/sbin/route) or tunnel restarted ***")
                } else {
                    interceptedRoutes.append(route)
                }
            }
        }
        return 0
    }
    
    func deleteRoute(_ destinationAddress: String) -> Int32 {
        let (dest, subnetMask) = cidrToDestAndMask(destinationAddress)
        
        if let dest = dest, let subnetMask = subnetMask {
            zLog.info("deleteRoute \(dest) => \(dest), \(subnetMask)")
            let route = NEIPv4Route(destinationAddress: dest,
                                    subnetMask: subnetMask)
            
            if identitiesLoaded{
                zLog.warn("*** Unable to delete route for \(destinationAddress) on running tunnel.")
            } else {
                interceptedRoutes = interceptedRoutes.filter {
                    $0.destinationAddress == route.destinationAddress &&
                    $0.destinationSubnetMask == route.destinationSubnetMask
                }
            }
        }
        return 0
    }
    
    func excludeRoute(_ destinationAddress: String, _ loop: OpaquePointer?) -> Int32 {
        let (dest, subnetMask) = cidrToDestAndMask(destinationAddress)
        
        if let dest = dest, let subnetMask = subnetMask {
            zLog.info("excludeRoute \(dest) => \(dest), \(subnetMask)")
            let route = NEIPv4Route(destinationAddress: dest,
                                    subnetMask: subnetMask)
            
            // only exclude if haven't already..
            var alreadyExists = true
            if excludedRoutes.first(where: {
                                        $0.destinationAddress == route.destinationAddress &&
                                        $0.destinationSubnetMask == route.destinationSubnetMask}) == nil {
                alreadyExists = false
                excludedRoutes.append(route)
            }
            
            if identitiesLoaded && !alreadyExists {
                zLog.warn("*** Unable to exclude route for \(destinationAddress) on running tunnel")
            }
        }
        return 0
    }
    
    func initCallback(_ ziti:Ziti, _ error:CZiti.ZitiError?) {
        guard let tzid = zidToTzid(ziti.id) else {
            zLog.wtf("Unable to find identity \(ziti.id)")
            return
        }
        guard error == nil else {
            zLog.error("Unable to init \(tzid.name):\(tzid.id), err: \(error!.localizedDescription)")
            tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
            _ = zidStore.store(tzid)
            return
        }
        allZitis.append(ziti)
    }
    
    func tunnelEventCallback(_ event: ZitiTunnelEvent) {
        zLog.info(event.debugDescription)
        
        guard let ziti = event.ziti else {
            zLog.wtf("Invalid ziti context for event \(event.debugDescription)")
            return
        }
        guard let tzid = zidToTzid(ziti.id) else {
            zLog.wtf("Unable to find identity \(ziti.id)")
            return
        }
        
        tzid.czid = ziti.id
        let (cvers, _, _) = ziti.getControllerVersion()
        tzid.controllerVersion = cvers
        
        if let contextEvent = event as? ZitiTunnelContextEvent {
            handleContextEvent(ziti, tzid, contextEvent)
        } else if let apiEvent = event as? ZitiTunnelApiEvent {
            handleApiEvent(ziti, tzid, apiEvent)
        } else if let serviceEvent = event as? ZitiTunnelServiceEvent {
            handleServiceEvent(ziti, tzid, serviceEvent)
        } else if let _ = event as? ZitiTunnelMfaEvent {
            tzid.mfaPending = true
            tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
            
            userNotifications.post(.Mfa, "MFA Auth Requested", tzid.name, tzid)
            
            // MFA Notification not reliably shown, so force the auth request, since in some instances it's important MFA succeeds before identities are loaded
            tzid.addAppexNotification(IpcMfaAuthQueryMessage(tzid.id, nil))
            _ = zidStore.store(tzid)
        }
    }
    
    private func handleContextEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelContextEvent) {
        let (cvers, _, _) = ziti.getControllerVersion()
        let cVersion = "\(cvers)"
        if tzid.controllerVersion != cVersion {
            tzid.controllerVersion = cVersion
        }
        
        if event.status == "OK" { // hardocded string in TSDK. was Ziti.ZITI_OK {
            tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
        } else {
            tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .PartiallyAvailable)
        }
        
        _ = zidStore.store(tzid)
    }
    
    private func canDial(_ eSvc:CZiti.ZitiService) -> Bool {
        return (Int(eSvc.permFlags ?? 0x0) & Ziti.ZITI_CAN_DIAL != 0) && (eSvc.interceptConfigV1 != nil || eSvc.tunnelClientConfigV1 != nil)
    }
    
    private func containsNewRoute(_ zSvc:ZitiService) -> Bool {
        guard let addresses = zSvc.addresses else {
            return false
        }
        
        for addr in addresses.components(separatedBy: ",") {
            let (dest, subnetMask) = cidrToDestAndMask(addr)
            
            if let dest = dest, let subnetMask = subnetMask {
                let route = NEIPv4Route(destinationAddress: dest, subnetMask: subnetMask)
                if interceptedRoutes.first(where: {
                                            $0.destinationAddress == route.destinationAddress &&
                                            $0.destinationSubnetMask == route.destinationSubnetMask}) == nil {
                    return true
                }
            }
        }
        return false
    }
    
    private func containsNewDnsEntry(_ zSvc:ZitiService) -> Bool {
        guard let addresses = zSvc.addresses else {
            return false
        }
        for addr in addresses.components(separatedBy: ",") {
            if dnsEntries.dnsEntries.first(where: { $0.hostname == addr }) == nil {
                return true
            }
        }
        return false
    }
    
    private func processService(_ tzid:ZitiIdentity, _ eSvc:CZiti.ZitiService, remove:Bool=false, add:Bool=false) {
        guard let serviceId = eSvc.id else {
            zLog.error("invalid service for \(tzid.name):(\(tzid.id)), name=\(eSvc.name ?? "nil"), id=\(eSvc.id ?? "nil")")
            return
        }
        
        if remove {
            if !identitiesLoaded {
                self.dnsEntries.removeDnsEntry(serviceId)
            }
            tzid.services = tzid.services.filter { $0.id != serviceId }
        }
        
        if add {
            if canDial(eSvc) {
                let zSvc = ZitiService(eSvc)
                zSvc.addresses?.components(separatedBy: ",").forEach { addr in
                    let (ip, _) = cidrToDestAndMask(addr)
                    let isDNS = ip == nil
                    if !identitiesLoaded && isDNS {
                        dnsEntries.addDnsEntry(addr, "", serviceId)
                    } else if isDNS && providerConfig.interceptMatchedDns {
                        zLog.warn("*** Unable to add DNS support for \(addr) to running tunnel when intercepting by matched domains")
                    }
                }
                
                // check if restart is needed
                if identitiesLoaded {
                    // If intercepting by domains or has new route, needsRestart
                    if (providerConfig.interceptMatchedDns && containsNewDnsEntry(zSvc)) || containsNewRoute(zSvc) {
                        let msg = "Restart may be required to access service \"\(zSvc.name ?? "")\""
                        zLog.warn(msg)
                        userNotifications.post(.Restart, tzid.name, msg, tzid)
                        tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .PartiallyAvailable)
                        zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: true)
                    }
                }
                
                // check for failed posture checks
                let zidMgr = ZidMgr()
                if !zidMgr.postureChecksPassing(zSvc) {
                    let msg = "Failed posture check(s) for service \"\(zSvc.name ?? "")\""
                    zLog.warn(msg)
                    userNotifications.post(.Posture, tzid.name, msg, tzid)
                    
                    let needsRestart = zSvc.status?.needsRestart ?? false
                    tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .PartiallyAvailable)
                    zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Unavailable, needsRestart: needsRestart)
                }
                tzid.services.append(zSvc)
            }
        }
    }
    
    private func handleServiceEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelServiceEvent) {
        for eSvc in event.removed { processService(tzid, eSvc, remove:true) }
        for eSvc in event.added   { processService(tzid, eSvc, add:true) }
        
        let zidMgr = ZidMgr()
        if zidMgr.allServicePostureChecksPassing(tzid) && !zidMgr.needsRestart(tzid) {
            tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
        }
        _ = zidStore.store(tzid)
    }
    
    private func handleApiEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelApiEvent) {
        zLog.info("Saving zid file, newControllerAddress=\(event.newControllerAddress).")
        tzid.czid?.ztAPI = event.newControllerAddress
        _ = zidStore.store(tzid)
    }
    
    func dumpZitis() -> String {
        var str = ""
        let cond = NSCondition()
        var count = allZitis.count
        
        allZitis.forEach { z in
            z.perform {
                z.dump { str += $0; return 0 }

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
    
    override var debugDescription: String {
        return "PacketTunnelProvider \(self)\n\(self.providerConfig)"
    }
    
    func zidToTzid(_ zid:CZiti.ZitiIdentity) -> ZitiIdentity? {
        return zidToTzid(zid.id)
    }
    
    func zidToTzid(_ zid:String) -> ZitiIdentity? {
        if tzids != nil {
            for i in 0 ..< tzids!.count {
                guard let czid = tzids![i].czid else { continue }
                if czid.id == zid {
                    let (curr, zErr) = zidStore.load(czid.id)
                    if let curr = curr, zErr == nil {
                        tzids![i] = curr
                    }
                    return tzids![i]
                }
            }
        }
        return nil
    }
    
    var versionString:String {
        get {
            let z = Ziti(withId: CZiti.ZitiIdentity(id: "", ztAPI: ""))
            let (vers, rev, buildDate) = z.getCSDKVersion()
            return "\(Version.verboseStr); ziti-sdk-c version \(vers)-\(rev)(\(buildDate))"
        }
    }
}
