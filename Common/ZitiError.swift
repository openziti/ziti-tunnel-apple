//
//  ZitiError.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/2/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

struct ZitiError : LocalizedError, CustomNSError {
    public static var errorDomain:String = "Ziti"
    
    public var errorDescription:String?
    public var errorCode:Int = -1
    public var errorUserInfo:[String:Any] = [:]
    
    init(_ errorDescription:String) {
        NSLog(errorDescription)
        self.errorDescription = errorDescription
    }
}
