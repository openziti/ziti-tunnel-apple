//
//  ZitiEdgeNetworkSession.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/6/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiEdgeNetworkSession : Codable {
    class Gateway : Codable {
        var name:String?
        var hostname:String?
        var urls:[String]?
    }
    var name:String?
    var token:String?
    var gateways:[Gateway]?
}

class ZitiEdgeNetworkSessionResponse : Codable {
    class Meta : Codable {}
    var meta:Meta?
    var data:ZitiEdgeNetworkSession?
}
