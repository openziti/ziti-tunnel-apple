//
//  IPv6Packet.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 5/7/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

// TODO (currently set to 0 Target membership)
class IPv6Packet : NSObject, IPPacket {
    var data: Data
    
    var version: UInt8
    
    var protocolId: IPProtocolId
    
    var sourceAddress: Data
    
    var sourceAddressString: String
    
    var destinationAddress: Data
    
    var destinationAddressString: String
    
    var payload: Data?
    
    func createFromRefPacket(_ refPacket: IPPacket) -> IPPacket {
        // TODO
    }
    
    func updateLengthsAndChecksums() {
        // TODO
    }
    
    
}
