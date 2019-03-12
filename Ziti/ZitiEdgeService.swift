//
//  ZitiEdgeService.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/6/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

struct ZitiEdgeService : Codable {
    struct Dns : Codable {
        var hostname:String?
        var port:Int?
    }
    var name:String?
    var id:String?
    var dns:Dns?
}

struct ZitiEdgeServiceResponse : Codable {
    struct Meta : Codable {}
    var meta:Meta?
    var data:[ZitiEdgeService]?
}
