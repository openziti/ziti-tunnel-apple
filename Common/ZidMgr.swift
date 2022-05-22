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
import CommonCrypto
import CZiti

class ZidMgr : NSObject {
    var zids:[ZitiIdentity] = []
    var zidStore = ZitiIdentityStore()
    
    func loadZids() -> ZitiError? {
        let (zids, err) = zidStore.loadAll()
        guard err == nil else { return err }
                
        self.zids = zids ?? []
        return nil
    }
    
    func updateIdentity(_ zid:ZitiIdentity) {
        var found = false
        for i in 0..<zids.count {
            if zids[i].id == zid.id {
                zLog.info("\(zid.name):\(zid.id) CHANGED")
                found = true
                zids[i] = zid
                break
            }
        }
        if !found {
            zLog.info("\(zid.name):\(zid.id) NEW")
            zids.insert(zid, at:0)
        }
    }
    
    func needsRestart(_ zid:ZitiIdentity) -> Bool {
        var needsRestart = false
        if zid.isEnabled && zid.isEnrolled {
            let restarts = zid.services.filter {
                if let status = $0.status, let needsRestart = status.needsRestart {
                    return needsRestart
                }
                return false
            }
            needsRestart = restarts.count > 0
        }
        return needsRestart
    }
    
    func postureChecksPassing(_ svc:ZitiService) -> Bool {
        if let pqs = svc.postureQuerySets {
            for q in pqs {
                if q.isPassing ?? false {
                    return true
                }
            }
        }
        return false
    }
    
    func allServicePostureChecksPassing(_ zid:ZitiIdentity) -> Bool {
        for svc in zid.services {
            if !postureChecksPassing(svc) {
                return false
            }
        }
        return true
    }
    
    func failingPostureChecks(_ svc:ZitiService) -> [String] {
        var fails:[String] = []
        if let pqs = svc.postureQuerySets {
            for qs in pqs {
                if !(qs.isPassing ?? false) {
                    if let postureQueries = qs.postureQueries {
                        for q in postureQueries {
                            if !(q.isPassing ?? false) {
                                if let qt = q.queryType {
                                    fails.append(qt)
                                }
                            }
                        }
                    }
                }
            }
        }
        return Array(Set(fails)) // remove duplicates
    }
    
    func failingPostureChecks(_ zid:ZitiIdentity) -> [String] {
        var fails:[String] = []
        zid.services.forEach { svc in
            fails += failingPostureChecks(svc)
        }
        return Array(Set(fails))
    }
    
    func insertFromJWT(_ url:URL, at:Int) throws {
        let zid = ZitiIdentity()
        
        let enroller = ZitiEnroller(url.path)
        zid.claims = enroller.getClaims()
        
        guard let subj = zid.claims?.sub, let ztAPI =  zid.claims?.iss else {
            throw ZitiError("Invalid JWT claims")
        }
        zid.czid = CZiti.ZitiIdentity(id: subj, ztAPI: ztAPI, name: url.lastPathComponent)
        
        // only support OTT
        guard zid.getEnrollmentMethod() == .ott else {
            throw ZitiError("Only OTT Enrollment is supported by this application")
        }
        
        // alread have this one?
        guard zids.first(where:{$0.id == zid.id}) == nil else {
            throw ZitiError("Duplicate Identity Not Allowed. Identy \(zid.name) is already present with id \(zid.id)")
        }
        
        // save off the JWT (as id.name probably)
        if let error = zidStore.storeJWT(zid, url) { throw error }
        
        // store zid
        if let error = zidStore.store(zid) { throw error }
        
        // add it
        zids.insert(zid, at:at)
    }
}
