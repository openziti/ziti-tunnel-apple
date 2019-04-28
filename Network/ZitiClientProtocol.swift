//
//  ZitiClientProtocol.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/27/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

import NetworkExtension
import Foundation

protocol ZitiClientProtocol: class {
    typealias DataAvailableCallback = ((Data?, Int) -> Void)
    var onDataAvailable:DataAvailableCallback? { get set }
    
    func connect(_ onDataAvailable: @escaping DataAvailableCallback) -> Bool
    func write(payload:Data) -> Int
    func close()
}
