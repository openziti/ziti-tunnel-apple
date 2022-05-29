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

import Foundation
import NetworkExtension
import UserNotifications
import CZiti

class ZitiTunnelDelegate: NSObject, CZiti.ZitiTunnelProvider {
    static let MFA_POSTURE_CHECK_TIMER_INTERVAL:UInt64 = 30
    static let MFA_POSTURE_CHECK_FIRST_NOTICE:UInt64 = 300
    static let MFA_POSTURE_CHECK_FINAL_NOTICE:UInt64 = 120
    
    weak var ptp:PacketTunnelProvider?
    let userNotifications = UserNotifications.shared
    
    let zidStore = ZitiIdentityStore()
    var tzids:[ZitiIdentity]?
    var allZitis:[Ziti] = [] // for ziti.dump...
    var dnsEntries = DNSUtils.DnsEntries()
    var interceptedRoutes:[NEIPv4Route] = []
    var excludedRoutes:[NEIPv4Route] = []
    
    private var _identitesLoaded = false // when true, restart is required to update routes for services intercepted by IP
    var identitiesLoaded:Bool {
        set {
            _identitesLoaded = newValue
            
            // notifiy Ziti on unlock
            #if os(macOS)
                DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"), object:nil, queue: OperationQueue.main) { _ in
                    zLog.debug("---screen unlock----")
                    self.allZitis.forEach { $0.endpointStateChange(false, true) }
                }
            
            
                // set timer to check pending MFA posture timeouts
                allZitis.first?.startTimer(
                    ZitiTunnelDelegate.MFA_POSTURE_CHECK_TIMER_INTERVAL * 1000,
                    ZitiTunnelDelegate.MFA_POSTURE_CHECK_TIMER_INTERVAL * 1000) { _ in
                    self.onMfaPostureTimer()
                }
            #endif
        }
        get { return _identitesLoaded }
    }
    
    
    init(_ ptp:PacketTunnelProvider) {
        super.init()
        self.ptp = ptp
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        userNotifications.requestAuth()
    }
    
    func loadIdentites() -> ([CZiti.ZitiIdentity]?, ZitiError?) {
        let (tzids, zErr) = zidStore.loadAll()
        guard zErr == nil, let tzids = tzids else {
            return (nil, zErr)
        }
        self.tzids = tzids
                
        // create list of CZiti.ZitiIdenty type used by CZiti.ZitiTunnel
        var zids:[CZiti.ZitiIdentity] = []
        tzids.forEach { tzid in
            if let czid = tzid.czid, tzid.isEnabled == true {
                tzid.appexNotifications = nil
                tzid.services = []
                if tzid.isMfaEnabled {
                    tzid.mfaPending = true
                }
                tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .Unavailable)
                _ = zidStore.store(tzid)
                zids.append(czid)
            }
        }
        return (zids, nil)
    }

    func initCallback(_ ziti: Ziti, _ error: CZiti.ZitiError?) {
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
    
    func addRoute(_ destinationAddress: String) -> Int32 {
        let (dest, subnetMask) = cidrToDestAndMask(destinationAddress)
        
        if let dest = dest, let subnetMask = subnetMask {
            zLog.info("addRoute \(dest) => \(dest), \(subnetMask)")
            let route = NEIPv4Route(destinationAddress: dest, subnetMask: subnetMask)
            
            var alreadyExists = true
            if interceptedRoutes.first(where: { IPUtils.areSameRoutes($0, route) }) == nil {
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
            if excludedRoutes.first(where: { IPUtils.areSameRoutes($0, route) }) == nil {
                alreadyExists = false
                excludedRoutes.append(route)
            }
            
            if identitiesLoaded && !alreadyExists {
                zLog.warn("*** Unable to exclude route for \(destinationAddress) on running tunnel")
            }
        }
        return 0
    }
    
    func writePacket(_ data: Data) {
        ptp?.writePacket(data)
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
            //tzid.addAppexNotification(IpcMfaAuthQueryMessage(tzid.id, nil))
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
                if interceptedRoutes.first(where: { IPUtils.areSameRoutes($0, route) }) == nil {
                    return true
                }
            }
        }
        return false
    }
    
    private func containsNewDnsEntry(_ zSvc:ZitiService) -> Bool {
        if let addresses = zSvc.addresses  {
            for addr in addresses.components(separatedBy: ",") {
                if dnsEntries.contains(addr) {
                    return true
                }
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
                self.dnsEntries.remove(serviceId)
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
                        dnsEntries.add(addr, "", serviceId)
                    } else if isDNS && (ptp?.providerConfig.interceptMatchedDns ?? true) {
                        zLog.warn("*** Unable to add DNS support for \(addr) to running tunnel when intercepting by matched domains")
                    }
                }
                
                // check if restart is needed
                if identitiesLoaded {
                    // If intercepting by domains or has new route, needsRestart
                    if ((ptp?.providerConfig.interceptMatchedDns ?? true) && containsNewDnsEntry(zSvc)) || containsNewRoute(zSvc) {
                        let msg = "Restart may be required to access service \"\(zSvc.name ?? "")\""
                        zLog.warn(msg)
                        userNotifications.post(.Restart, tzid.name, msg, tzid)
                        tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .PartiallyAvailable)
                        zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .PartiallyAvailable, needsRestart: true)
                    }
                }
                
                // check for failed posture checks
                if !zSvc.postureChecksPassing() {
                    let msg = "Failed posture check(s) for service \"\(zSvc.name ?? "")\""
                    zLog.warn(msg)
                    userNotifications.post(.Posture, tzid.name, msg, tzid)
                    
                    let needsRestart = zSvc.status?.needsRestart ?? false
                    tzid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status: .PartiallyAvailable)
                    zSvc.status = ZitiService.Status(Date().timeIntervalSince1970, status: .Unavailable, needsRestart: needsRestart)
                }
                
                // if services are being added, MFA isn't pending...
                tzid.mfaPending = false
                
                // add the service
                tzid.services.append(zSvc)
            }
        }
    }
    
    private func handleServiceEvent(_ ziti:Ziti, _ tzid:ZitiIdentity, _ event:ZitiTunnelServiceEvent) {
        for eSvc in event.removed { processService(tzid, eSvc, remove:true) }
        for eSvc in event.added   { processService(tzid, eSvc, add:true) }
        
        if tzid.allServicePostureChecksPassing() && !tzid.needsRestart() {
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
        return (dest.trimmingCharacters(in: .whitespaces), subnetMask.trimmingCharacters(in: .whitespaces))
    }
    
    func onMfaPostureTimer() {
        guard let tzids = tzids else { return }
        
        let now = Date()
        let firstNoticeMin = ZitiTunnelDelegate.MFA_POSTURE_CHECK_FIRST_NOTICE - ZitiTunnelDelegate.MFA_POSTURE_CHECK_TIMER_INTERVAL
        let finalNoticeMin = ZitiTunnelDelegate.MFA_POSTURE_CHECK_FINAL_NOTICE - ZitiTunnelDelegate.MFA_POSTURE_CHECK_TIMER_INTERVAL
        
        for tzid in tzids {
            
            // if already failing posture checks don't bother (user notification was already sent)
            if !tzid.isEnabled || !tzid.isEnrolled || !tzid.allServicePostureChecksPassing() {
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
            if lowestTimeRemaining > firstNoticeMin && lowestTimeRemaining < ZitiTunnelDelegate.MFA_POSTURE_CHECK_FIRST_NOTICE {
                self.userNotifications.post(.Mfa, "MFA Auth Posture Check",
                                            "\(tzid.name) MFA expiring in less then \(UInt64(ZitiTunnelDelegate.MFA_POSTURE_CHECK_FIRST_NOTICE/60)) mins",
                                            tzid)
            } else if lowestTimeRemaining > finalNoticeMin && lowestTimeRemaining < ZitiTunnelDelegate.MFA_POSTURE_CHECK_FINAL_NOTICE {
                self.userNotifications.post(.Mfa, "MFA Auth Posture Check",
                                            "\(tzid.name) MFA expiring in less then \(ZitiTunnelDelegate.MFA_POSTURE_CHECK_FINAL_NOTICE/60) mins",
                                            tzid)
            }
        }
    }
}

extension ZitiTunnelDelegate: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // On macOS, method is not reliably called. When it is, results are ignored (notification is not displayed)
        zLog.error("willPresent: \(notification.request.content.subtitle), \(notification.request.content.body)")
        
        var actions:[String] = []
        if let category = UserNotifications.Category(rawValue: notification.request.content.categoryIdentifier) {
            actions = category.actions.map { $0.identifier }
        }
        if let zid = notification.request.content.userInfo["zid"] as? String, let tzid = zidToTzid(zid) {
            tzid.addAppexNotification(IpcAppexNotificationMessage(zid,
                notification.request.content.categoryIdentifier,
                notification.request.content.title,
                notification.request.content.subtitle,
                notification.request.content.body,
                actions))
            _ = zidStore.store(tzid)
        } else if let zid = tzids?.first?.id, let tzid = zidToTzid(zid)   {
            tzid.addAppexNotification(IpcAppexNotificationMessage(nil,
                notification.request.content.categoryIdentifier,
                notification.request.content.title,
                notification.request.content.subtitle,
                notification.request.content.body,
                actions))
            _ = zidStore.store(tzid)
        }
        completionHandler([]) // [.list, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // This is only called on macOS.  On iOS, the app's AppDelegate gets notified...
        zLog.debug("didReceive: \(response.notification.request.content.subtitle), \(response.notification.request.content.body)")
        
        if let zid = response.notification.request.content.userInfo["zid"] as? String, let tzid = zidToTzid(zid) {
            tzid.addAppexNotification(IpcAppexNotificationActionMessage(
                zid, response.notification.request.content.categoryIdentifier, response.actionIdentifier))
            _ = zidStore.store(tzid)
        } else if let zid = tzids?.first?.id, let tzid = zidToTzid(zid)   {
            tzid.addAppexNotification(IpcAppexNotificationActionMessage (
                nil, response.notification.request.content.categoryIdentifier, response.actionIdentifier))
            _ = zidStore.store(tzid)
        }
        completionHandler()
    }
}