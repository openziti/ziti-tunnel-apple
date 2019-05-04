//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class ZitiEdgeNetworkSession : Codable {
    struct Gateway : Codable {
        var name:String?
        var hostname:String?
        var urls:[String:String]?
        
        init(from:Any) throws {
            let data = try JSONSerialization.data(withJSONObject:from, options: [])
            self = try JSONDecoder().decode(Gateway.self, from: data)
            let json = try JSONSerialization.jsonObject(with:data, options:[]) as? [String: Any]
            urls = json?["urls"] as? [String:String]
        }
    }
    var id:String?
    var token:String?
    var gateways:[Gateway]?
}

class ZitiEdgeNetworkSessionResponse : Codable {
    class Meta : Codable {}
    var meta:Meta?
    var data:ZitiEdgeNetworkSession?
}
