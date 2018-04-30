//
//  DNSProxy.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/25/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation
import NetworkExtension

class DNSProxy : NSObject {
     // DNS is fast (usu wll under .1 secs), standard time-out of macOS to resend is 5 secs
    static let requestTimeout:TimeInterval = 2.5
    static let superOldThreshold:TimeInterval = requestTimeout * 3.0
    
    let tunnelProvider:PacketTunnelProvider
    
    // pending request queue while we wait for session to be established
    private var pendingRequestQueue:[DNSPacket] = []
    
    // cache requests while we wait for reply from remote DNS server
    typealias DNSRequestHash = [UInt16:(src:UDPPacket, timeSent:TimeInterval)]
    private var requestCache:DNSRequestHash = [:]
    
    // track servers with last time each failed to aide algorythm for selecting server when one fails
    typealias DNSServerEntry = (address:String, lastFailedAt:TimeInterval)
    typealias DNSServerArray = [DNSServerEntry]
    var dnsServers:DNSServerArray = []
    
    init(_ tunnelProvider:PacketTunnelProvider) {
        self.tunnelProvider = tunnelProvider
        
        super.init()
        
        self.tunnelProvider.providerConfig.dnsProxyAddresses.forEach { addr in
            self.dnsServers.append((addr, lastFailedAt:0))
        }
        self.currDNSServer = self.dnsServers[0]
    }
    
    static let defaultDDNSServer = DNSServerEntry("1.1.1.1", 0)
    var currDNSServer:DNSServerEntry = defaultDDNSServer
    
    var nextDNSServer:DNSServerEntry {
        get {
            // find dnsServer that has failed least recently (or the first one if none have failed)
            let currTime = NSDate().timeIntervalSince1970
            let maxEntry = self.dnsServers.max(by: { e1, e2 in
                return (currTime - e2.lastFailedAt) > (currTime - e1.lastFailedAt)
            })
            
            if let maxEntry = maxEntry {
                self.currDNSServer = maxEntry
                return maxEntry
            }
            
            NSLog("DNSProxy: Unable to find valid DNS server, using default \(DNSProxy.defaultDDNSServer.address)")
            self.currDNSServer = DNSProxy.defaultDDNSServer
            return DNSProxy.defaultDDNSServer
        }
    }
    
    private func handleDNSError(requestCache:DNSRequestHash) {
        // Udate failed time for whichever is curr DNS
        let now = NSDate().timeIntervalSince1970
        self.dnsServers = self.dnsServers.map { entry in
            if entry.address == self.currDNSServer.address {
                return DNSServerEntry(entry.address, lastFailedAt:now)
            } else {
                return entry
            }
        }
        
        // force create of new session (only if alternate DNS available...)
        if self.dnsServers.count > 1 {
            self.session = nil
            
            // clear outstanding requests
            self.requestCache = [:]
            
            // re-send any that weren't reaped
            requestCache.forEach { entry in
                self.proxyDnsMessage(DNSPacket(entry.value.src)!)
            }
        }
    }
    
    // prune timed-out requests (give proxied DNS .5 secs to respond)
    private func reapRequestCache() {
        NSLog("DNSProxy: reapiing from \(self.requestCache.count)")
        var newCache:DNSRequestHash = [:]
        var maxAge:TimeInterval = 0.0
        
        // gotta loop through the hash (it shouldn't ever be very large...)
        self.requestCache.forEach { entry in
            let age = NSDate().timeIntervalSince1970 - entry.value.timeSent
            maxAge = max(age, maxAge)
            if age < DNSProxy.requestTimeout {
                newCache[entry.key] = entry.value
            }
        }
        
        let reapCount = self.requestCache.count - newCache.count
        NSLog("DNSProxy: reaped \(reapCount) entries, maxAge=\(maxAge)")
        
        // Check if we are getting flooded
        //
        // If we have *really* old ones it means nobody haa tried to use DNS in a while,.
        // possibly since we timed out and the OS is looking elsewhere for DNS and is getting back to trying us again,
        // or maybe there are message outstanding from restarting the tunnel. If this is the case then
        // just go on our merry way.
        //
        // But if we are reaping any, see if we are configured for alternate DNS servers and try
        // another of 'em.
        //
        if maxAge < DNSProxy.superOldThreshold && reapCount > 0 {
            NSLog("*** DNSPRoxy timeout.")
            self.handleDNSError(requestCache:newCache)
        } else {
            self.requestCache = newCache
        }
    }
    
    // What I'm going for here is a lazy property inialization that I can set to nill
    // and have re-init next time I access it...
    private func createSession() -> NWUDPSession {
        let address = self.nextDNSServer.address
        let session =  self.tunnelProvider.createUDPSession(
            to: NWHostEndpoint(hostname: address, port: String(DNSResolver.dnsPort)),
            from: nil)
        session.setReadHandler(self.handleDnsResponse, maxDatagrams: NSIntegerMax)
        return session
    }
    
    private var _session:NWUDPSession? = nil
    private var session:NWUDPSession? {
        get {
            if self._session == nil {
                self._session = createSession()
                self._session?.addObserver(self, forKeyPath: "state", options: .new, context: &self._session)
            }
            return self._session!
        }
        
        set {
            self._session = newValue
        }
    }
    
    private func handleDnsResponse(packets:[Data]?, error:Error?) {
        if let error = error {
            NSLog("Error handling read from forwarding DNS packet \(error)")
            self.handleDNSError(requestCache: [:])
            return
        }
        
        if let packets = packets {
            for udpPayload in packets {
                let transactionId = IPv4Utils.extractUInt16(udpPayload, from: DNSPacket.idOffset)
                if let udpRequest = self.requestCache.removeValue(forKey: transactionId) {
                    let udpResponse = UDPPacket(udpRequest.src, payload:udpPayload)
                    udpResponse.updateLengthsAndChecksums()
                    
                    //NSLog("<--DNS: \(DNSPacket(udpResponse).debugDescription)")
                    NSLog("<--UDP: \(udpResponse.debugDescription)")
                    NSLog("<--IP: \(udpResponse.ip.debugDescription)")
                    self.tunnelProvider.packetFlow.writePackets([udpResponse.ip.data], withProtocols: [AF_INET as NSNumber])
                } else {
                    NSLog("Unable to corrolate DNS response to request for transactionId \(transactionId)")
                }
            }
        }
    }
    
    // Implementation of KVO state observer to send pending requests
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        guard keyPath == "state" && context?.assumingMemoryBound(to: Optional<NWTCPConnection>.self).pointee == self._session else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if let session = self._session {
            NSLog("DNS UDP session state changed to \(session.state)")
            switch session.state {
            case .ready:
                self.pendingRequestQueue.forEach { dns in
                    NSLog("...Forwarding DNS packet to \(self.currDNSServer)")
                    self.requestCache[dns.id] = (dns.udp, NSDate().timeIntervalSince1970)
                    session.writeDatagram(dns.udp.payload!, completionHandler: { error in
                        if let e = error {
                            NSLog("Error forwarding DNS packet \(e)")
                        }
                    })
                }
                session.removeObserver(self, forKeyPath: "state", context:&self._session)
            case .cancelled, .invalid, .failed:
                session.removeObserver(self, forKeyPath: "state", context:&self._session)
            case .preparing, .waiting:
                NSLog("...Still waiting for valid session")
                break
            }
        }
    }
    
    func proxyDnsMessage(_ dns:DNSPacket) {
        
        // clean-up any timed-out requests
        self.reapRequestCache()
        
        if let udpPayload = dns.udp.payload {
            if let session = self.session {
                switch session.state {
                case .ready:
                    NSLog("...Forwarding DNS packet to \(self.currDNSServer)")
                    
                    // cache the request so we know how to respond
                    self.requestCache[dns.id] = (dns.udp, NSDate().timeIntervalSince1970)
                    session.writeDatagram(udpPayload, completionHandler: { error in
                        if let e = error {
                            NSLog("Error forwarding DNS packet \(e)")
                        }
                    })
                case .cancelled, .failed, .invalid:
                    NSLog("...Dropping DNS packet - forwarding session in invalid state \(session.state.rawValue). Will re-create on next send...")
                    // setting session to nil will cause it to auto-recreate next time it's accessed (if ever)
                    self.session = nil
                case .preparing, .waiting:
                    NSLog("...Forwarding session not yet ready \(session.state.rawValue), will send when it is")
                    // pending requests are handled by the KVO ssession state observer
                    self.pendingRequestQueue.append(dns)
                }
            }
        }
    }
}
