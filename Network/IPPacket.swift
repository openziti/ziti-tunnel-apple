//
//  IPPacket.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 5/6/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

enum IPProtocolId : UInt8 {
    case TCP = 6
    case UDP = 17
    case other
    
    init(_ byte:UInt8) {
        switch byte {
        case  6: self = .TCP
        case 17: self = .UDP
        default: self = .other
        }
    }
}

protocol IPPacket  {
    var data:Data { get set }
    
    var version:UInt8 { get }
    var protocolId:IPProtocolId { get }
    
    var sourceAddress : Data { get set }
    var sourceAddressString: String { get }
    
    var destinationAddress:Data { get set }
    var destinationAddressString: String { get }
    
    var payload:Data? { get set }
    
    var debugDescription: String { get }
    
    func createFromRefPacket(_ refPacket:IPPacket) -> IPPacket
    func updateLengthsAndChecksums()
}
