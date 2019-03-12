//
//  ZitiEdgeNetworkSession.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/6/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

struct ZitiEdgeNetworkSession : Codable {
    struct Gateway : Codable {
        var name:String?
        var hostname:String?
        var urls:[String]?
    }
    var name:String?
    var token:String?
    var gateways:[Gateway]?
}

struct ZitiEdgeNetworkSessionResponse : Codable {
    struct Meta : Codable {}
    var meta:Meta?
    var data:ZitiEdgeNetworkSession?
}
