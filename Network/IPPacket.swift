//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

enum IPProtocolId : UInt8 {
    case ICMP = 1
    case TCP = 6
    case UDP = 17
    case other
    
    init(_ byte:UInt8) {
        switch byte {
        case  1: self = .ICMP
        case  6: self = .TCP
        case 17: self = .UDP
        default: self = .other
        }
    }
}

protocol IPPacket  {
    var data:Data { get set }
    var version:UInt8 { get }
    var protocolId:IPProtocolId { get set }
    var sourceAddress : Data { get set }
    var sourceAddressString: String { get }
    var destinationAddress:Data { get set }
    var destinationAddressString: String { get }
    var payload:Data? { get set }
    var debugDescription: String { get }
    func createFromRefPacket(_ refPacket:IPPacket) -> IPPacket
    func updateLengthsAndChecksums()
}
