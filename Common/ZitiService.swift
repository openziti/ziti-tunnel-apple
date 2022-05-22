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

class ZitiService : Codable {
    class Status : Codable {
        let lastUpdatedAt:TimeInterval
        let status:ZitiIdentity.ConnectivityStatus
        var needsRestart:Bool?
        init(_ lastUpdatedAt:TimeInterval, status:ZitiIdentity.ConnectivityStatus, needsRestart:Bool=false) {
            self.lastUpdatedAt = lastUpdatedAt
            self.status = status
            self.needsRestart = needsRestart
        }
    }
    var name:String?
    var id:String?
    var protocols:String?
    var addresses:String?
    var portRanges:String?
    var status:Status?
    var postureQuerySets:[CZiti.ZitiPostureQuerySet]?
    
    init(_ eSvc:CZiti.ZitiService) {
        name = eSvc.name
        id = eSvc.id
        postureQuerySets = eSvc.postureQuerySets
        
        if let cfg = eSvc.interceptConfigV1 {
            protocols = cfg.protocols.joined(separator: ", ").uppercased()
            addresses = cfg.addresses.sorted().joined(separator: ", ")
            var prArr:[String] = []
            cfg.portRanges.forEach { pr in
                if pr.low == pr.high {
                    prArr.append("\(pr.low)")
                } else {
                    prArr.append("\(pr.low)-\(pr.high)")
                }
            }
            portRanges = prArr.sorted().joined(separator: ", ")
        } else if let cfg = eSvc.tunnelClientConfigV1 {
            protocols = "TCP, UDP"
            addresses = cfg.hostname
            portRanges = "\(cfg.port)"
        }
        status = ZitiService.Status(Date().timeIntervalSince1970, status: .Available, needsRestart: false)
    }
    
    func postureChecksPassing() -> Bool {
        if let pqs = postureQuerySets {
            for q in pqs {
                if q.isPassing ?? false {
                    return true
                }
            }
        }
        return false
    }
    
    func failingPostureChecks() -> [String] {
        var fails:[String] = []
        if let pqs = postureQuerySets {
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
}
