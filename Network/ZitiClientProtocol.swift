//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

import NetworkExtension
import Foundation

protocol ZitiClientProtocol: class {
    var key:String { get set }
    typealias DataAvailableCallback = ((Data?, Int) -> Void)
    var onDataAvailable:DataAvailableCallback? { get set }
    var releaseConnection:(()->Void)? { get set }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool
    func write(payload:Data) -> Int
    func close()
}
