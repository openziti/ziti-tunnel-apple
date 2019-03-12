//
//  ZitiIdentityStore.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/24/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiIdentityStore : NSObject, NSFilePresenter {
    
    // TODO: Get TEAMID programatically... (and will be diff on iOS)
    static let APP_GROUP_ID = "45L2MKV8H4.ZitiPacketTunnel.group"
    
    var presentedItemURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: APP_GROUP_ID)
    lazy var presentedItemOperationQueue = OperationQueue.main
    
    override init() {
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    
    func load() -> ([ZitiIdentity]?, ZitiError?) {
        guard self.presentedItemURL != nil else {
            return (nil, ZitiError("Unable to load identities. Invalid container URL"))
        }
        
        var zIds:[ZitiIdentity] = []
        var zErr:ZitiError? = nil
        let fc = NSFileCoordinator()
        fc.coordinate(readingItemAt: presentedItemURL!, options: .withoutChanges, error: nil) { url in
            do {
                let list = try FileManager.default.contentsOfDirectory(at: self.presentedItemURL!, includingPropertiesForKeys: nil, options: [])
                try list.forEach { url in
                    NSLog("found id \(url.absoluteString)")
                    
                    if url.pathExtension == "zid" {
                        let data = try Data.init(contentsOf: url)
                        let jsonDecoder = JSONDecoder()
                        if let zId = try? jsonDecoder.decode(ZitiIdentity.self, from: data) {
                            zIds.append(zId)
                        } else {
                            // log it and continue (don't return error and abort)
                            NSLog("ZitiIdentityStore.load failed loading \(url.absoluteString)")
                        }
                    }
                }
            } catch {
                zErr = ZitiError("ZitiIdentityStore.load Unable to read directory URL: \(error.localizedDescription)")
            }
        }
        guard zErr == nil else {
            return (nil, zErr)
        }
        return (zIds, nil)
    }
    
    func store(_ zId:ZitiIdentity) -> ZitiError? {
        guard self.presentedItemURL != nil else {
            return ZitiError("ZitiIdentityStore.store: Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = self.presentedItemURL!.appendingPathComponent("\(zId.id).zid", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: [], error: nil) { url in
            do {
                let jsonEncoder = JSONEncoder()
                let data = try jsonEncoder.encode(zId)
                try data.write(to: url, options: .atomic)
            } catch {
                zErr = ZitiError("ZitiIdentityStore.store Unable to write URL: \(error.localizedDescription)")
            }
        }
        return zErr
    }
    
    func remove(_ zId:ZitiIdentity) -> ZitiError? {
        guard self.presentedItemURL != nil else {
            return ZitiError("ZitiIdentityStore.remove: Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = self.presentedItemURL!.appendingPathComponent("\(zId.id).zid", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: .forDeleting, error: nil) { url in
            do {
                let zkc = ZitiKeychain(zId)
                _ = zkc.deleteCertificate()
                _ = zkc.deleteKeyPair()
                try FileManager.default.removeItem(at: url)
            } catch {
                zErr = ZitiError("ZitiIdentityStore.remove Unable to delete zId: \(error.localizedDescription)")
            }
        }
        return zErr
    }
    
    func presentedSubitemDidChange(at url: URL) {
        NSLog("CHANGE: \(url.absoluteString)")
    }
    
    func presentedSubitemDidAppear(at url: URL) {
        NSLog("NEW: \(url.absoluteString)")
    }
}
