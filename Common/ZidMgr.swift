//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
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
