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

extension ZitiIdentity {
    /// Host and port, with the https default, so "https://CTRL" and "https://ctrl:443/edge/client/v1" are the same controller
    static func endpoint(_ url:URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return "\(host):\(url.port ?? 443)"
    }

    /// Host, plus the port when given, to show the user
    static func controllerName(_ url:URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// Whether one of the identity's controllers has the same host and port, enrolled or not
    func isOnController(_ controller:URL) -> Bool {
        guard let czid = czid, let target = ZitiIdentity.endpoint(controller) else { return false }
        return ([czid.ztAPI] + (czid.ztAPIs ?? [])).contains { URL(string: $0).flatMap(ZitiIdentity.endpoint) == target }
    }
}

extension Array where Element == ZitiIdentity {
    /// An identity not yet enrolled, added for the controller from a controller URL, or from a network JWT
    /// (links, URLs and files are easy to add twice)
    func pending(controller:URL, networkJwt:Bool) -> ZitiIdentity? {
        return first { zid in
            guard !zid.isEnrolled, zid.isOnController(controller) else { return false }
            return networkJwt ? zid.claims?.em == "network" : zid.claims == nil
        }
    }

    /// Refuses a second identity waiting to enroll the same way with the same controller
    private func checkNotPending(controller:URL, networkJwt:Bool) throws {
        if let zid = pending(controller: controller, networkJwt: networkJwt) {
            throw ZitiError("\(zid.name) is already waiting to enroll with \(ZitiIdentity.controllerName(controller))")
        }
    }

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
    
    /// Drops an identity the store reported removed. nil when the list doesn't have it: the app removed it itself, or
    /// enrollment gave it its real id (the store then reports the temporary id as removed)
    mutating func removeReported(_ id:String) -> ZitiIdentity? {
        guard let indx = firstIndex(where: { $0.id == id }) else { return nil }
        return remove(at: indx)
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

        let em = zid.getEnrollmentMethod()
        guard em == .ott || em == .unrecognized || em == .url else {
            throw ZitiError("Unsupported enrollment method: \(zid.claims?.em ?? "unknown")")
        }

        if zid.claims?.em == "network", let controller = URL(string: ztAPI) {
            try checkNotPending(controller: controller, networkJwt: true)
        }

        // OTT uses subject as identity ID; network JWTs use a temp UUID
        let idStr = (em == .ott) ? subj : UUID().uuidString
        zid.czid = CZiti.ZitiIdentity(id: idStr, ztAPIs: [ztAPI], name: url.lastPathComponent)

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
    
    mutating func insertFromURL(_ url:URL, _ zidStore:ZitiIdentityStore, at:Int) throws {
        guard let host = url.host else { throw ZitiError("No host in controller URL") }
        try checkNotPending(controller: url, networkJwt: false)
        // a temp id, like network JWTs: the host alone isn't unique (one host can serve several networks on different ports)
        let zid = ZitiIdentity()
        zid.czid = CZiti.ZitiIdentity(id: UUID().uuidString, ztAPIs: [url.absoluteString], name: host)

        // store zid
        if let error = zidStore.store(zid) { throw error }
        
        // add it
        self.insert(zid, at:at)
    }
}
