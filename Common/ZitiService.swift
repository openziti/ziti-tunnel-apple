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

class ZitiService : Codable {
    class Dns : Codable {
        var hostname:String?
        var interceptIp:String?
        var port:Int?
    }
    class Status : Codable {
        let lastUpdatedAt:TimeInterval
        let status:ZitiIdentity.ConnectivityStatus
        var needsRestart:Bool?
        init(_ lastUpdatedAt:TimeInterval, status:ZitiIdentity.ConnectivityStatus, needsRestart:Bool=false) {
            self.lastUpdatedAt = lastUpdatedAt
            self.status = status
            self.needsRestart = needsRestart
        }
    }
    var name:String?
    var id:String?
    var dns:Dns?
    var status:Status?
}
