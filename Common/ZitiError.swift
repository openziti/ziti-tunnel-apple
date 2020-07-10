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

class ZitiError : LocalizedError, CustomNSError {
    public static var errorDomain:String = "ZitiError"
    public static let URLError = -1000
    public static let AuthRequired = 401
    public static let NoSuchFile = 260
    
    public var errorDescription:String?
    public var errorCode:Int = -1
    public var errorUserInfo:[String:Any] = [:]
    
    init(_ errorDescription:String, errorCode:Int=Int(-1)) {
        NSLog("\(errorCode) \(errorDescription)")
        self.errorDescription = errorDescription
        self.errorCode = errorCode
    }
}
