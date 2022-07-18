//
// Copyright NetFoundry, Inc.
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

extension Array where Element == ZitiIdentity {
    mutating func updateIdentity(_ zid:ZitiIdentity) {
        var found = false
        for i in 0..<count {
            if self[i].id == zid.id {
                zLog.info("\(zid.name):\(zid.id) CHANGED")
                found = true
                self[i] = zid
                break
            }
        }
        if !found {
            zLog.info("\(zid.name):\(zid.id) NEW")
            self.insert(zid, at:0)
        }
    }
    
    func getZidIndx(_ zidStr:String?) -> Int {
        guard let zidStr = zidStr else {
            return -1
        }

        var indx = -1
        for i in 0..<self.count {
            if self[i].id == zidStr {
                indx = i
                break
            }
        }
        return indx
    }
    
    mutating func insertFromJWT(_ url:URL, _ zidStore:ZitiIdentityStore, at:Int) throws {
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
        guard self.first(where:{$0.id == zid.id}) == nil else {
            throw ZitiError("Duplicate Identity Not Allowed. Identy \(zid.name) is already present with id \(zid.id)")
        }
        
        // save off the JWT (as id.name probably)
        if let error = zidStore.storeJWT(zid, url) { throw error }
        
        // store zid
        if let error = zidStore.store(zid) { throw error }
        
        // add it
        self.insert(zid, at:at)
    }
}
