//
//  ZitiEdgeError.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/6/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

struct ZitiEdgeError : Codable {
    struct Cause : Codable {
        var message:String?
        var fieldName:String?
        var fieldValue:String?
    }
    var cause:Cause?
    var causeMessage:String?
    var code:String?
    var message:String?
    var requestId:String?
}

struct ZitiEdgeErrorResponse : Codable {
    struct Meta : Codable {
        var apiVersion:String?
        var apiEnrolmentVersion:String?
    }
    var meta:Meta?
    var error:ZitiEdgeError?
    
    func shortDescription(_ httpStatusCode:Int) -> String {
        let statusStr = HTTPURLResponse.localizedString(forStatusCode: httpStatusCode)
        var respStr = "HTTP response code: \(httpStatusCode) \(statusStr)"
        if (error != nil) {
            if (error!.cause?.message?.count ?? 0 > 0) {
                respStr += "\n\(error!.cause!.message!)"
            } else if (error!.causeMessage?.count ?? 0 > 0) {
                respStr += "\n\(error!.causeMessage!)"
            }
        }
        return respStr
    }
}
