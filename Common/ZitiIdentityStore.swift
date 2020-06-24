//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import CZiti

protocol ZitiIdentityStoreDelegate: class {
    func onNewOrChangedId(_ zid:ZitiIdentity)
    func onRemovedId(_ idString:String)
}

class ZitiIdentityStore : NSObject, NSFilePresenter {
    
    // TODO: Get TEAMID programatically... (and will be diff on iOS)
    #if os(macOS)
    static let APP_GROUP_ID = "MN5S649TXM.ZitiPacketTunnel.group"
    #else
    static let APP_GROUP_ID = "group.io.netfoundry.ZitiMobilePacketTunnel"
    #endif
    
    var presentedItemURL:URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)
    lazy var presentedItemOperationQueue = OperationQueue.main
    var haveFilePresenter = false
    weak var delegate:ZitiIdentityStoreDelegate?
    
    override init() { }
    deinit { }
    
    func loadAll() -> ([ZitiIdentity]?, ZitiError?) {
        guard let presentedItemURL = self.presentedItemURL else {
            return (nil, ZitiError("Unable to load identities. Invalid container URL"))
        }
        
        var zIds:[ZitiIdentity] = []
        var zErr:ZitiError? = nil
        let fc = NSFileCoordinator()
        fc.coordinate(readingItemAt: presentedItemURL, options: .withoutChanges, error: nil) { url in
            do {
                if haveFilePresenter == false {
                    NSFileCoordinator.addFilePresenter(self)
                    haveFilePresenter = true
                }
                let list = try FileManager.default.contentsOfDirectory(at: self.presentedItemURL!, includingPropertiesForKeys: nil, options: [])
                try list.forEach { url in
                    if url.pathExtension == "zid" {
                        NSLog("found id \(url.lastPathComponent)")
                        let data = try Data.init(contentsOf: url)
                        let jsonDecoder = JSONDecoder()
                        if let zId = try? jsonDecoder.decode(ZitiIdentity.self, from: data) {
                            if zId.czid == nil {
                                NSLog("ZitiIdentityStore.load failed loading \(url.lastPathComponent).  Unsupported version")
                            } else {
                                zIds.append(zId)
                            }
                        } else {
                            // log it and continue (don't return error and abort)
                            NSLog("ZitiIdentityStore.load failed loading \(url.lastPathComponent)")
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
    
    func load(_ idString:String) -> (ZitiIdentity?, ZitiError?) {
        guard let presentedItemURL = self.presentedItemURL else {
            return (nil, ZitiError("ZitiIdentityStore.load: Invalid container URL"))
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(idString).zid", isDirectory:false)
        var zErr:ZitiError?
        var zid:ZitiIdentity?
        fc.coordinate(readingItemAt:url, options:.withoutChanges, error:nil) { url in
            do {
                let data = try Data.init(contentsOf: url)
                let jsonDecoder = JSONDecoder()
                zid = try jsonDecoder.decode(ZitiIdentity.self, from: data)
            } catch let error as NSError where error.code == ZitiError.NoSuchFile {
                zErr = ZitiError("ZitiIdentityStore unable to load zid \(idString): \(error.localizedDescription)", errorCode:ZitiError.NoSuchFile)
            } catch {
                zErr = ZitiError("ZitiIdentityStore unable to load zid \(idString): \(error.localizedDescription)")
            }
        }
        return (zid, zErr)
    }
    
    func store(_ zId:ZitiIdentity) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("ZitiIdentityStore.store: Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zId.id).zid", isDirectory:false)
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
    
    func storeJWT(_ zId:ZitiIdentity, _ jwtOrig:URL) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("ZitiIdentityStore.store: Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zId.id).jwt", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: [], error: nil) { url in
            do {
                let data = try Data(contentsOf: jwtOrig)
                try data.write(to: url, options: .atomic)
            } catch {
                zErr = ZitiError("ZitiIdentityStore.store Unable store JWT URL: \(error.localizedDescription)")
            }
        }
        return zErr
    }
    
    func remove(_ zid:ZitiIdentity) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("ZitiIdentityStore.remove: Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zid.id).zid", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: .forDeleting, error: nil) { url in
            do {
                if let czid = zid.czid {
                    Ziti(withId: czid).forget()
                }
                try FileManager.default.removeItem(at: url)
            } catch {
                zErr = ZitiError("ZitiIdentityStore.remove Unable to delete zId: \(error.localizedDescription)")
            }
        }
        if zErr == nil { _ = removeJWT(zid) }
        return zErr
    }
    
    func removeJWT(_ zid:ZitiIdentity) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("ZitiIdentityStore.removeCId: Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: .forDeleting, error: nil) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                zErr = ZitiError("ZitiIdentityStore.removeJWT Unable to delete JWT: \(error.localizedDescription)")
            }
        }
        return zErr
    }
    
    func finishAndRelease() {
        if haveFilePresenter == true {
            NSFileCoordinator.removeFilePresenter(self)
        }
    }
    
    func presentedSubitemDidChange(at url: URL) {
        guard let delegate = self.delegate else { return }
        if url.pathExtension == "zid" {
            let split = url.lastPathComponent.split(separator: ".")
            if let id = split.first {
                let (zid, zErr) = load(String(id))
                if zErr != nil, zErr?.errorCode == ZitiError.NoSuchFile {
                    delegate.onRemovedId(String(id))
                }
                guard zid != nil else { return }
                delegate.onNewOrChangedId(zid!)
            }
        }
    }
    
    // This is never called.  Per Internet, its a bug in Apple code
    // will have to use SubitemDidChange
    //func presentedSubitemDidAppear(at url: URL) {
      //  NSLog("NEW: \(url.lastPathComponent)") /
    //}
}