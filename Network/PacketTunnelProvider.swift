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
            zLog.wtf("Unable to startTunnel. Invalid providerConfiguration. \(error)")
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
        zitiTunnel = ZitiTunnel(self, providerConfig.ipAddress, providerConfig.subnetMask, ipDNS, upstreamDns)
        
        // read in the .zid files
        let (tzids, zErr) = zidStore.loadAll()
        guard zErr == nil, let tzids = tzids else {
            zLog.error("Error loading .zid files: \(zErr != nil ? zErr!.localizedDescription : "uknown")")
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
                completionHandler(zErr)
                return
            }
            self.identitiesLoaded = true
            
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
                
                // call completion handler with nil to indicate success
                completionHandler(nil)
                
                // Start listening for traffic headed our way via the tun interface
                self.readPacketFlow()
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        //let dumpStr = dumpZitis()
        //zLog.info(dumpStr)
        
        guard let zitiTunnel = zitiTunnel else {
            zLog.error("No valid zitiTunnel context found. Exiting.")
            exit(EXIT_SUCCESS)
        }
        
        zitiTunnel.shutdownZiti {
            completionHandler()
            zLog.info("Exiting")
            exit(EXIT_SUCCESS)
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
        //zLog.debug("---Wake---")
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
    
    func cidrToDestAndMask(_ cidr:String) -> (String?, String?) {
        var dest = cidr
        var prefix:UInt32 = 32
        
        let parts = dest.components(separatedBy: "/")
        guard (parts.count == 1 || parts.count == 2) && IPUtils.isValidIpV4Address(parts[0]) else {
            zLog.error("Invalid CIDR: \(cidr)")
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
                interceptedRoutes.append(route)
            }
            
            if identitiesLoaded && !alreadyExists {
                zLog.warn("*** Unable to add route for \(destinationAddress) to running tunnel. " +
                        "If route not already available it must be manually added (/sbin/route) or tunnel re-started ***")
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
            
            interceptedRoutes = interceptedRoutes.filter {
                $0.destinationAddress == route.destinationAddress &&
                $0.destinationSubnetMask == route.destinationSubnetMask
            }
            
            if identitiesLoaded{
                zLog.warn("*** Unable to add route for \(destinationAddress) to running tunnel. " +
                        "If route not already available it must be manually added (/sbin/route) or tunnel re-started ***")
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
    
    private func processService(_ tzid:ZitiIdentity, _ eSvc:CZiti.ZitiService, remove:Bool=false, add:Bool=false) {
        guard let serviceId = eSvc.id else {
            zLog.error("invalid service for \(tzid.name):(\(tzid.id)), name=\(eSvc.name ?? "nil"), id=\(eSvc.id ?? "nil")")
            return
        }
        
        if remove {
            self.dnsEntries.removeDnsEntry(serviceId)
            tzid.services = tzid.services.filter { $0.id != serviceId }
        }
        
        if add {
            if canDial(eSvc) {
                let zSvc = ZitiService(eSvc)
                zSvc.addresses?.components(separatedBy: ",").forEach { addr in
                    if !IPUtils.isValidIpV4Address(addr) {
                        dnsEntries.addDnsEntry(addr, "", serviceId)
                    }
                }
                if identitiesLoaded { // TODO: need to check if DNS && providerConfig.interceptMatchedDns or if IP address for needsReset.  need to set edgeStatus.  Also - edgeStatus if mfaEnbled and pending...
                    zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: true)
                }
                tzid.services.append(zSvc)
            }
        }
    }
    
    private func handleServiceEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelServiceEvent) {
        for eSvc in event.removed { processService(tzid, eSvc, remove:true) }
        for eSvc in event.added   { processService(tzid, eSvc, add:true) }

        // Update controller status to .Available
        tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
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
        guard var tzids = tzids else {
            zLog.wtf("Invalid identity list")
            return nil
        }

        for i in 0 ..< tzids.count {
            guard let czid = tzids[i].czid else { continue }
            if czid.id == zid.id {
                let (curr, zErr) = zidStore.load(czid.id)
                if let curr = curr, zErr == nil {
                    tzids[i] = curr
                }
                return tzids[i]
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
