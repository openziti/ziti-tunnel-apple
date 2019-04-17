//
//  ZidMgr.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/14/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation
import JWTDecode

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
        let token = try String(contentsOf: url, encoding: .utf8)
        let jwt = try decode(jwt: token)
        
        // parse the body
        guard let data = try? JSONSerialization.data(withJSONObject:jwt.body),
            let zid = try? JSONDecoder().decode(ZitiIdentity.self, from: data)
            else {
                throw ZitiError("Unable to parse enrollment data")
        }
        
        // only support OTT
        guard zid.method == .ott else {
            throw ZitiError("Only OTT Enrollment is supported by this application")
        }
        
        // alread have this one?
        guard zids.first(where:{$0.id == zid.id}) == nil else {
            throw ZitiError("Duplicate Identity Not Allowed. Identy \(zid.name) is already present with id \(zid.id)")
        }
        
        // store it
        if let error = zidStore.store(zid) {
            throw error
        }
        
        // add it
        zids.insert(zid, at:at)
    }
}
