//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class ZitiEdgeService : Codable {
    class Dns : Codable {
        var hostname:String?
        var interceptIp:String?
        var port:Int?
    }
    class Status : Codable {
        let lastUpdatedAt:TimeInterval
        let status:ZitiIdentity.ConnectivityStatus
        init(_ lastUpdatedAt:TimeInterval, status:ZitiIdentity.ConnectivityStatus) {
            self.lastUpdatedAt = lastUpdatedAt
            self.status = status
        }
    }
    var name:String?
    var id:String?
    var dns:Dns?
    var networkSession:ZitiEdgeNetworkSession?
    var status:Status?
}

class ZitiEdgeServiceResponse : Codable {
    class Meta : Codable {}
    var meta:Meta?
    var data:[ZitiEdgeService]?
}
