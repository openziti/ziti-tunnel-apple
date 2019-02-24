//
//  ZitiIdentityStore.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/24/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiIdentityStore : NSObject, NSFilePresenter {
    var presentedItemURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ZitiIdentity.APP_GROUP_ID)
    lazy var presentedItemOperationQueue = OperationQueue.main
    
    override init() {
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    
    func load() -> [ZitiIdentity] {
        guard self.presentedItemURL != nil else {
            NSLog("ZitiIdentityStore.load: Invalid container URL")
            return []
        }
        
        var zIds:[ZitiIdentity] = []
        let fc = NSFileCoordinator()
        fc.coordinate(readingItemAt: presentedItemURL!, options: .withoutChanges, error: nil) { url in
            do {
                let list = try FileManager.default.contentsOfDirectory(at: self.presentedItemURL!, includingPropertiesForKeys: nil, options: [])
                try list.forEach { url in
                    NSLog("found id \(url.absoluteString)")
                    
                    if url.pathExtension == "zid" {
                        let data = try Data.init(contentsOf: url)
                        if let zId = NSKeyedUnarchiver.unarchiveObject(with: data) as? ZitiIdentity {
                            zIds.append(zId)
                            print("ZitiIdentityStore.load appended zId \(zId.name): \(zId.id)")
                        }
                    }
                }
            } catch {
                NSLog("ZitiIdentityStore.load Unable to read directory URL: \(error.localizedDescription)")
            }
        }
        return zIds
    }
    
    func store(_ zId:ZitiIdentity) {
        guard self.presentedItemURL != nil else {
            NSLog("ZitiIdentityStore.store: Invalid container URL")
            return
        }
        
        let fc = NSFileCoordinator()
        let url = self.presentedItemURL!.appendingPathComponent("\(zId.id).zid", isDirectory:false)
        print("Storing url \(url.absoluteString)")
        fc.coordinate(writingItemAt: url, options: [], error: nil) { url in
            let data = NSKeyedArchiver.archivedData(withRootObject: zId)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("ZitiIdentityStore.store Unable to write URL: \(error.localizedDescription)")
            }
        }
    }
    
    func remove(_ zId:ZitiIdentity) {
        guard self.presentedItemURL != nil else {
            NSLog("ZitiIdentityStore.remove: Invalid container URL")
            return
        }
        
        let fc = NSFileCoordinator()
        let url = self.presentedItemURL!.appendingPathComponent("\(zId.id).zid", isDirectory:false)
        print("Deleting url \(url.absoluteString)")
        fc.coordinate(writingItemAt: url, options: .forDeleting, error: nil) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                NSLog("ZitiIdentityStore.remove Unable to delete zId: \(error.localizedDescription)")
            }
        }
    }
    
    func presentedSubitemDidChange(at url: URL) {
        NSLog("CHANGE: \(url.absoluteString)")
    }
    
    func presentedSubitemDidAppear(at url: URL) {
        NSLog("NEW: \(url.absoluteString)")
    }
}
