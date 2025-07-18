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

import Foundation
import CZiti

protocol ZitiIdentityStoreDelegate: AnyObject {
    func onNewOrChangedId(_ zid:ZitiIdentity)
    func onRemovedId(_ idString:String)
}

class ZitiIdentityStore : NSObject, NSFilePresenter {
    
    enum UpdateOptions {
        case Replace
        case Enabled
        case Enrolled
        case EdgeStatus
        case ControllerVersion
        case CZitiIdentity
        case Mfa
        case ExtAuth
        case Services
        case AppexNotifications
    }
    
    var presentedItemURL:URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.APP_GROUP_ID)
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
                        zLog.debug("found id \(url.lastPathComponent)")
                        let data = try Data.init(contentsOf: url)
                        let jsonDecoder = JSONDecoder()
                        if let zId = try? jsonDecoder.decode(ZitiIdentity.self, from: data) {
                            if zId.czid == nil {
                                zLog.error("failed loading \(url.lastPathComponent).  Unsupported version")
                            } else {
                                zIds.append(zId)
                            }
                        } else {
                            // log it and continue (don't return error and abort)
                            zLog.error("failed loading \(url.lastPathComponent)")
                        }
                    }
                }
            } catch {
                zErr = ZitiError("Unable to read directory URL: \(error.localizedDescription)")
            }
        }
        guard zErr == nil else {
            return (nil, zErr)
        }
        return (zIds, nil)
    }
    
    func load(_ idString:String) -> (ZitiIdentity?, ZitiError?) {
        guard let presentedItemURL = self.presentedItemURL else {
            return (nil, ZitiError("Invalid container URL"))
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(idString).zid", isDirectory:false)
        var zErr:ZitiError?
        var zid:ZitiIdentity?
        fc.coordinate(readingItemAt:url, options:[], error:nil) { url in
            autoreleasepool {
                do {
                    let data = try Data.init(contentsOf: url)
                    let jsonDecoder = JSONDecoder()
                    zid = try jsonDecoder.decode(ZitiIdentity.self, from: data)
                } catch let error as NSError where error.code == ZitiError.NoSuchFile {
                    zErr = ZitiError("Unable to load zid \(idString): \(error.localizedDescription)", errorCode:ZitiError.NoSuchFile)
                } catch {
                    zErr = ZitiError("Unable to load zid \(idString): \(error.localizedDescription)")
                }
            }
        }
        return (zid, zErr)
    }
    
    func store(_ zId:ZitiIdentity) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zId.id).zid", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: [], error: nil) { url in
            autoreleasepool {
                do {
                    let jsonEncoder = JSONEncoder()
                    let data = try jsonEncoder.encode(zId)
                    try data.write(to: url, options: .atomic)
                } catch {
                    zErr = ZitiError("Unable to write URL: \(error.localizedDescription)")
                }
            }
        }
        return zErr
    }
    
    func update(_ zid:ZitiIdentity, _ options:[UpdateOptions]) -> ZitiIdentity {
        guard let presentedItemURL = self.presentedItemURL else {
            zLog.wtf("Invalid container URL")
            return zid
        }
        
        // short circuit Replace option
        if options.contains(.Replace) {
            if let zErr = store(zid) {
                zLog.error("Error replacing identity \(zid.name):\(zid.id): \(zErr.localizedDescription)")
            }
            return zid
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zid.id).zid", isDirectory:false)
        var zidOnDisk:ZitiIdentity?
        fc.coordinate(readingItemAt: url, writingItemAt: url, error: nil) { readURL, writeURL in
            // read from disk
            var readError = false
            autoreleasepool {
                do {
                    let data = try Data.init(contentsOf: readURL)
                    let jsonDecoder = JSONDecoder()
                    zidOnDisk = try jsonDecoder.decode(ZitiIdentity.self, from: data)
                } catch {
                    zLog.error("Unable to load zid \(zid.name):\(zid.id) - \(error.localizedDescription)")
                    zidOnDisk = zid
                    readError = true
                }
            }
            if readError {
                return
            }
            
            // update per options
            if options.contains(.Enabled) {
                zidOnDisk?.enabled = zid.enabled
            }
            if options.contains(.Enrolled) {
                zidOnDisk?.enrolled = zid.enrolled
            }
            if options.contains(.EdgeStatus) {
                zidOnDisk?.edgeStatus = zid.edgeStatus
            }
            if options.contains(.ControllerVersion) {
                zidOnDisk?.controllerVersion = zid.controllerVersion
            }
            if options.contains(.CZitiIdentity) {
                zidOnDisk?.czid = zid.czid
            }
            if options.contains(.AppexNotifications) {
                zidOnDisk?.appexNotifications = zid.appexNotifications
            }
            if options.contains(.Mfa) {
                zidOnDisk?.mfaEnabled = zid.mfaEnabled
                zidOnDisk?.mfaPending = zid.mfaPending
                zidOnDisk?.mfaVerified = zid.mfaVerified
                zidOnDisk?.lastMfaAuth = zid.lastMfaAuth
            }
            if options.contains(.Services) {
                zidOnDisk?.services = zid.services
            }
            if options.contains(.ExtAuth) {
                zidOnDisk?.jwtProviders = zid.jwtProviders
                zidOnDisk?.extAuthPending = zid.extAuthPending
            }
            
            // store to disk
            autoreleasepool {
                do {
                    let jsonEncoder = JSONEncoder()
                    let data = try jsonEncoder.encode(zidOnDisk)
                    try data.write(to: writeURL, options: .atomic)
                } catch {
                    zLog.error("Unable to store zid \(zid.name):\(zid.id) - \(error.localizedDescription)")
                }
            }
        }
        return zidOnDisk ?? zid
    }
    
    func storeJWT(_ zId:ZitiIdentity, _ jwtOrig:URL) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zId.id).jwt", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: [], error: nil) { url in
            autoreleasepool {
                do {
                    let data = try Data(contentsOf: jwtOrig)
                    try data.write(to: url, options: .atomic)
                } catch {
                    zErr = ZitiError("Unable store JWT URL: \(error.localizedDescription)")
                }
            }
        }
        return zErr
    }
    
    func remove(_ zid:ZitiIdentity) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("Invalid container URL")
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
                zErr = ZitiError("Unable to delete zId: \(error.localizedDescription)")
            }
        }
        if zErr == nil { _ = removeJWT(zid) }
        return zErr
    }
    
    func removeJWT(_ zid:ZitiIdentity) -> ZitiError? {
        guard let presentedItemURL = self.presentedItemURL else {
            return ZitiError("Invalid container URL")
        }
        
        let fc = NSFileCoordinator()
        let url = presentedItemURL.appendingPathComponent("\(zid.id).jwt", isDirectory:false)
        var zErr:ZitiError? = nil
        fc.coordinate(writingItemAt: url, options: .forDeleting, error: nil) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                zErr = ZitiError("Unable to delete JWT: \(error.localizedDescription)")
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
            let id = url.deletingPathExtension().lastPathComponent
            let (zid, zErr) = load(String(id))
            if zErr != nil, zErr?.errorCode == ZitiError.NoSuchFile {
                delegate.onRemovedId(String(id))
            }
            guard zid != nil else { return }
            delegate.onNewOrChangedId(zid!)
        }
    }
    
    // This is never called.  Per Internet, its a bug in Apple code
    // will have to use SubitemDidChange
    //func presentedSubitemDidAppear(at url: URL) {
      //  zLog.info("NEW: \(url.lastPathComponent)") /
    //}
}
