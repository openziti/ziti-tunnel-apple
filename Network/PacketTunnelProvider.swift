//
// Copyright NetFoundry Inc.
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

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    let providerConfig = ProviderConfig()
    var appLogLevel:ZitiLog.LogLevel?
    let netMon = NWPathMonitor()
    var zitiTunnel:ZitiTunnel?
    var zitiTunnelDelegate:ZitiTunnelDelegate?
    var writeLock = NSLock()
    var ipcServer:IpcAppexServer?
    let userNotifications = UserNotifications.shared
    
    override init() {
        super.init()
        
        Logger.initShared(Logger.TUN_TAG)
        zLog.debug("")
        zLog.info(versionString)
        
        CZiti.Ziti.setAppInfo(Bundle.main.bundleIdentifier ?? "Ziti", Version.str)
        
        // Give a short timeout for services to load, avoiding need to reassert tunnel networking settings
        // (and associated user notification)
        CZiti.ZitiTunnel.SERVICE_WAIT_TIMEOUT = 5.0
        
        zitiTunnelDelegate = ZitiTunnelDelegate(self)
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
        
        guard let zitiTunnelDelegate = zitiTunnelDelegate else {
            let errStr = "Unable to start tunnel. Invalid provider tunnel delegate."
            zLog.wtf(errStr)
            userNotifications.post(.Error, nil, errStr)
            completionHandler(ZitiError(errStr))
            return
        }
        
        // load config
        if let error = loadConfig() {
            let errStr = "Unable to start tunnel. Invalid provider configuration. \(error)"
            zLog.wtf(errStr)
            userNotifications.post(.Error, nil, errStr)
            completionHandler(error)
            return
        }
        
        // setup log rotation
        Logger.updateRotateSettings(providerConfig.logRotateDaily, providerConfig.logRotateCount, providerConfig.logRotateSizeMB)
        
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
        let ipDNS = providerConfig.dnsAddresses.first ?? ""
        zitiTunnel = ZitiTunnel(zitiTunnelDelegate, providerConfig.ipAddress, providerConfig.subnetMask, ipDNS)
        
        if let upstreamDns = getUpstreamDns() {
            if zitiTunnel?.setUpstreamDns(upstreamDns) != 0 {
                zLog.warn("Unable to set upstream D?NS to \(upstreamDns)")
            }
        }
        
        // read in the .zid files
        let (zids, zErr) = zitiTunnelDelegate.loadIdentites()
        guard zErr == nil else  {
            let errStr = "Unable load identities. \(zErr!.localizedDescription)"
            zLog.error(errStr)
            userNotifications.post(.Error, nil, errStr)
            completionHandler(zErr!)
            return
        }
        
        guard let czids = zids else {
            let errStr = "Unable load identities"
            zLog.error(errStr)
            userNotifications.post(.Error, nil, errStr)
            completionHandler(ZitiError(errStr))
            return
        }
        
        // start 'er up
        zitiTunnel?.startZiti(czids, ZitiPostureChecks()) { zErr in
            guard zErr == nil else {
                let errStr = "Unable to load identites: \(zErr!.localizedDescription)"
                zLog.error(errStr)
                self.userNotifications.post(.Error, nil, errStr)
                completionHandler(zErr)
                return
            }
            self.zitiTunnelDelegate?.onIdentitiesLoaded()
            
            // watch for interface changes
            self.startNetworkMonitor()
            
            // identies have loaded, so go ahead and setup the TUN
            self.updateTunnelNetworkSettings { error in
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
    
    func loadConfig() -> Error? {
        guard let conf = (self.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration as? ProviderConfigDict else {
            let errStr = "Unable to load configuration. Provider configuration not available"
            zLog.wtf(errStr)
            userNotifications.post(.Error, nil, errStr)
            return ZitiError(errStr)
        }
        
        if let error = self.providerConfig.parseDictionary(conf) {
            let errStr = "Unable to load configuration: \(error.localizedDescription)"
            zLog.wtf(errStr)
            userNotifications.post(.Error, nil, errStr)
            return error
        }
        
        zLog.info("\(self.providerConfig.debugDescription)")
        return nil
    }
    
    func updateTunnelNetworkSettings(_ completionHandler: @escaping (Error?) -> Void) {
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        let dnsSettings = NEDNSSettings(servers: self.providerConfig.dnsAddresses)
        
        if self.providerConfig.interceptMatchedDns {
            // Add in all the hostnames we want to intercept as 'matchDomains'. We might get some extras, but that's ok...
            var matchDomains = self.zitiTunnelDelegate?.dnsEntries.hostnames.map { // trim of "*." for wildcard domains
                $0.starts(with: "*.") ? String($0.dropFirst(2)) : $0
            }
            
            // Make sure we don't become primary resolver (specified by having name = "")
            matchDomains = matchDomains?.filter { $0 != "" }
            if matchDomains?.count ?? 0 == 0 {
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
                self.zitiTunnelDelegate?.interceptedRoutes.append(NEIPv4Route(destinationAddress: svr, subnetMask: "255.255.255.255"))
            }
        }
        
        tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [providerConfig.ipAddress], subnetMasks: [providerConfig.subnetMask])
        let includedRoute = NEIPv4Route(destinationAddress: providerConfig.ipAddress, subnetMask: providerConfig.subnetMask)
        if zitiTunnelDelegate?.interceptedRoutes.first(where: { IPUtils.areSameRoutes($0, includedRoute) }) == nil {
            zitiTunnelDelegate?.interceptedRoutes.append(includedRoute)
        }
        
        zitiTunnelDelegate?.interceptedRoutes.forEach { r in
            zLog.info("route: \(r.destinationAddress) / \(r.destinationSubnetMask)")
        }
        zitiTunnelDelegate?.excludedRoutes.forEach { r in
            zLog.info("excluding route: \(r.destinationAddress) / \(r.destinationSubnetMask)")
        }
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = self.zitiTunnelDelegate?.interceptedRoutes
        tunnelNetworkSettings.ipv4Settings?.excludedRoutes = self.zitiTunnelDelegate?.excludedRoutes
        tunnelNetworkSettings.mtu = self.providerConfig.mtu as NSNumber
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            completionHandler(error)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        zitiTunnelDelegate?.shuttingDown()
        
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
        
        // shutdown tun (prob not necessary, but it seems to speed up the shutodwn)
        self.setTunnelNetworkSettings(nil)
                
        // shutdown all the ziti stuff
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
        // only sleep/wake on macOS for now. The happens way too often on mobile to be useful
#if os(macOS)
        zLog.info("---Sleep---")
        if providerConfig.lowPowerMode {
            self.zitiTunnel?.perform {
                self.zitiTunnelDelegate?.onSleep(completionHandler)
            }
        } else {
            completionHandler()
        }
#else
        completionHandler()
#endif
    }
    
    override func wake() {
#if os(macOS)
        zLog.info("---Wake---")
        zitiTunnel?.perform {
            self.zitiTunnelDelegate?.onWake()
        }
#endif
    }
    
    func readPacketFlow() {
        packetFlow.readPacketObjects { (packets:[NEPacket]) in
            zLog.trace("read \(packets.count) packets")
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
    
    func dumpZitis() -> String {
        return zitiTunnelDelegate?.dumpZitis() ?? ""
    }
    
    func getUpstreamDns() -> String? {
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
                var excludedRoute:NEIPv4Route?
                if let ipDNS = providerConfig.dnsAddresses.first {
                    excludedRoute = NEIPv4Route(destinationAddress: ipDNS, subnetMask: "255.255.255.255")
                }
                let firstResolver = DNSUtils.getFirstResolver(excludedRoute)
                if let fr = firstResolver {
                    zLog.warn("No fallback DNS configured. Setting to first resolver: \(fr)")
                }
                upstreamDns = firstResolver
            }
            
            if upstreamDns == nil {
                upstreamDns = "1.1.1.1"
                zLog.warn("No fallback DNS available. Defaulting to \(upstreamDns!)")
            }
        #endif
        
        return upstreamDns
    }
    
    func setUpstreamDns(_ upstreamDns:String, _ attemptNum:Int=1) {
        // This rots.  After tunnels starts, when network monitor detects newly satisfied status the initial
        // attempt to set this address for upstream DNS fails. So we're gonna retry it...
        let nAttempts = 3
        let waitInterval = 1.0 / Double(nAttempts)
        if attemptNum <= nAttempts {
            zitiTunnel?.perform {
                if self.zitiTunnel?.setUpstreamDns(upstreamDns) != 0 {
                    zLog.error("Attempt \(attemptNum) of \(nAttempts) failed setting upstream DNS to \(upstreamDns)")
                    DispatchQueue.global().async {
                        Thread.sleep(forTimeInterval: waitInterval)
                        self.setUpstreamDns(upstreamDns, attemptNum + 1)
                    }
                }
            }
        }
    }
    
    func startNetworkMonitor() {
        netMon.pathUpdateHandler = { path in
            self.logNetworkPath(path)
            
            if path.status == .satisfied {
                if let upstreamDns = self.getUpstreamDns() {
                    self.zitiTunnel?.perform {
                        zLog.info("Setting fallback DNS to \(upstreamDns)")
                        self.setUpstreamDns(upstreamDns)
                    }
                }
            }
            //isSatisfied = path.status == .satisfied
        }
        netMon.start(queue: DispatchQueue.global())
    }
    
    func logNetworkPath(_ path:Network.NWPath) {
        var ifaceStr = ""
        for i in path.availableInterfaces {
            ifaceStr += " \n     \(i.index): name:\(i.name), type:\(i.type)"
        }
        zLog.info("Network Path Update:\nStatus:\(path.status), Expensive:\(path.isExpensive), Cellular:\(path.usesInterfaceType(.cellular)), DNS:\(path.supportsDNS)\n   Interfaces:\(ifaceStr)")
    }
    
    override var debugDescription: String {
        return "PacketTunnelProvider \(self)\n\(self.providerConfig)"
    }
    
    var versionString:String {
        get {
            let z = Ziti(withId: CZiti.ZitiIdentity(id: "", ztAPI: ""))
            let (vers, rev, buildDate) = z.getCSDKVersion()
            return "\(Version.verboseStr); ziti-sdk-c version \(vers)-\(rev)(\(buildDate))"
        }
    }
}
