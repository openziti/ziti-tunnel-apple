//
//  ZitiEdgeService.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/6/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiEdgeService : Codable {
    class Dns : Codable {
        var hostname:String?
        var port:Int?
    }
    var name:String?
    var id:String?
    var dns:Dns?
    var networkSession:ZitiEdgeNetworkSession?
}

class ZitiEdgeServiceResponse : Codable {
    class Meta : Codable {}
    var meta:Meta?
    var data:[ZitiEdgeService]?
}
