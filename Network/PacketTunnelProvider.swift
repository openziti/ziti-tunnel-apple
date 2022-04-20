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
    let netMon = NWPathMonitor()
    var allZitis:[Ziti] = [] // for ziti.dump...
    var zitiTunnel:ZitiTunnel!
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
        zitiTunnel = ZitiTunnel(self, providerConfig.ipAddress, providerConfig.subnetMask, ipDNS, "1.1.1.1") // TODO: upstreamDNS.config?
        
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
                tzid.services = []
                tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                _ = zidStore.store(tzid)
                zids.append(czid)
            }
        }
        
        // start 'er up
        zitiTunnel.startZiti(zids, ZitiPostureChecks()) { zErr in
            guard zErr == nil else {
                zLog.error("Unable to load identites: \(zErr!.localizedDescription)")
                completionHandler(zErr)
                return
            }
            self.identitiesLoaded = true
            
            // identies have loaded, so go ahead and setup the TUN
            let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
            let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
            
            #if true // intercept_by_match_domains
                // Add in all the hostnames we want to intercept as 'matchDomains'. We'll get some extras, but that's ok, we'll proxy 'em...
                var matchDomains = self.dnsEntries.hostnames.map { // trim of "*." for wildcard domains
                    $0.starts(with: "*.") ? String($0.dropFirst(2)) : $0 // shaky. come back to this
                }
                
                // Make sure we don't become primary resolver (specified by having name = "")
                matchDomains = matchDomains.filter { $0 != "" }
                if matchDomains.count == 0 {
                    matchDomains = [ "ziti-test.netfoundry.io" ]
                }
                dnsSettings.matchDomains = matchDomains
            #else
                // intercept and proxy all to upstream DNS
                dnsSettings.matchDomains = [""] //self.providerConfig.dnsMatchDomains
            #endif
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
            tunnelNetworkSettings.ipv4Settings?.includedRoutes = self.interceptedRoutes
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
        completionHandler()
        // Just exit - there are bugs in Apple macOS, plus makes sure we're 'clean' on restart
        zLog.info("")
        exit(EXIT_SUCCESS)
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        zLog.info("")
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
        
        if identitiesLoaded && !alreadyExists {
            zLog.warn("*** Unable to add route for \(dest) to running tunnel. " +
                    "If route not already available it must be manually added (/sbin/route) or tunnel re-started ***")
        } else {
            zLog.info("Adding route for \(dest).")
        }
        return 0
    }
    
    func deleteRoute(_ dest: String) -> Int32 {
        zLog.warn("*** Unable to remove route for \(dest) on running tunnel. " +
                "If route not already available it must be manually removed (/sbin/route) or tunnel re-started ***")
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
        
        if let contextEvent = event as? ZitiTunnelContextEvent {
            handleContextEvent(ziti, tzid, contextEvent)
        } else if let apiEvent = event as? ZitiTunnelApiEvent {
            zLog.warn("TODO: apiEvent \(apiEvent.newControllerAddress)")
            handleApiEvent(ziti, tzid, apiEvent)
        } else if let serviceEvent = event as? ZitiTunnelServiceEvent {
            handleServiceEvent(ziti, tzid, serviceEvent)
        } else if let mfaEvent = event as? ZitiTunnelMfaEvent {
            zLog.warn("TODO: mfaEvent \(mfaEvent.operation) not implemented")
            /* Code when handling event directly from C-SDK (the only MFA event I expect - not sure what's going on with TunnelEvent for MFA...
             case .MfaAuth:
                 self.ipcServer?.queueMsg(IpcMfaAuthQueryMessage(zid.id, zEvent.mfaAuthEvent?.mfaAuthQuery))
             */
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
                if identitiesLoaded {
                    // TODO: Consider changing this to an IpcMessage indicating restart required?  Of, just have the appReact that way
                    // based on detecting needsRestart...
                    zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: true)
                }
                tzid.services.append(zSvc)
            }
        }
    }
    
    private func handleServiceEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelServiceEvent) {
        if event.removed.count > 0 || event.added.count > 0 {
            zLog.info("\(tzid.name):(\(tzid.id)) \(event.debugDescription)")
        }
        
        for eSvc in event.removed { processService(tzid, eSvc, remove:true) }
        for eSvc in event.added   { processService(tzid, eSvc, add:true) }

        // Update controller status to .Available
        tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Available)
        _ = zidStore.store(tzid)
    }
    
    private func handleApiEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelApiEvent) {
        zLog.info("Saving zid file, newControllerAddress=\(event.newControllerAddress).")
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
        guard let tzids = tzids else {
            zLog.wtf("Invalid identity list")
            return nil
        }
        for tzid in tzids {
            guard let czid = tzid.czid else { continue }
            if czid.id == zid.id {
                return tzid
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
