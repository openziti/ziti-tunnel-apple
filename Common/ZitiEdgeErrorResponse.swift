//
//  ZitiEdgeError.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/6/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiEdgeErrorMeta : NSObject, Codable {
    var apiVersion:String?
    var apiEnrolmentVersion:String?
}

class ZitiEdgeErrorCause : NSObject, Codable {
    var message:String?
    var fieldName:String?
    var fieldValue:String?
}

class ZitiEdgeError : NSObject, Codable {
    var cause:ZitiEdgeErrorCause?
    var causeMessage:String?
    var code:String?
    var message:String?
    var requestId:String?
}

class ZitiEdgeErrorResponse : NSObject, Codable {
    var meta:ZitiEdgeErrorMeta?
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
