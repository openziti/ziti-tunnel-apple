//
// Copyright 2020 NetFoundry, Inc.
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
import CZiti

#if os(macOS)
import ZitiPosture
#endif

class ZitiPostureChecks : CZiti.ZitiPostureChecks {
    var type:String?, strVers:String?, buildStr:String?
    
    #if os(macOS)
    let service:ZitiPostureProtocol?
    #endif
    
    override init() {
        // just get these once...
        (type, strVers, buildStr) = ZitiPostureChecks.getOsInfo()
        
#if os(macOS)
        // setup XPC
        let connection = NSXPCConnection(serviceName: "io.netfoundry.ZitiPacketTunnel.ZitiPosture")
        connection.remoteObjectInterface = NSXPCInterface(with: ZitiPostureProtocol.self)
        connection.resume()

        service = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("Received error getting proxy for ZitPosture XPC Service: \(error)")
        } as? ZitiPostureProtocol
#endif
        
        super.init()
        self.macQuery = macQueryImpl
        self.processQuery = processQueryImpl
        self.domainQuery = domainQueryImpl
        self.osQuery = osQueryImpl
    }
    
    func macQueryImpl(_ ctx:ZitiPostureContext, _ cb: @escaping MacResponse) {
        // these can be changed without rebooting, so get them every time...
        let macAddrs = ZitiPostureChecks.getMacAddrs()
        NSLog("MAC Posture Response: \(String(describing: macAddrs))")
        cb(ctx, macAddrs)
    }
    
    func processQueryImpl(_ ctx:ZitiPostureContext, _ path:String, _ cb: @escaping ProcessResponse) {
#if os(macOS)
        guard let service = service else {
            NSLog("ZitiPosture XPC Servicex not available.")
            cb(ctx, path, false, nil, nil)
            return
        }
        service.processQuery(path) { isRunning, hashString, signers in
            NSLog("Process Posture Response: path=\(path), isRunning=\(isRunning), hash=\(hashString ?? "nil"), signers=\(signers ?? [])")
            cb(ctx, path, isRunning, hashString, signers)
        }
#else
        cb(ctx, path, false, nil, nil)
#endif
    }
    
    func domainQueryImpl(_ ctx:ZitiPostureContext, _ cb: @escaping DomainResponse) {
        NSLog("Domain Posture Query - Unimplemented")
        cb(ctx, nil)
    }
    
    func osQueryImpl(_ ctx:ZitiPostureContext, _ cb: @escaping OsResponse) {
        NSLog("OS Posture Response: type=\(type ?? "nil"), vers=\(strVers ?? ""), build=\(buildStr ?? "")")
        cb(ctx, type, strVers, buildStr)
    }
    
    static func getMacAddrs() -> [String]? {
        var strs:[String]?
        let addrs = get_mac_addrs();
        if var ptr = addrs {
            strs = []
            while let s = ptr.pointee {
                strs?.append(String(cString:s))
                ptr += 1
            }
        }
        free_string_array(addrs)
        if strs != nil { strs = Array(Set(strs!)) } // remove duplicates
        return strs
    }
    
    static func getOsInfo() -> (String?, String?, String?) {
        let vers = ProcessInfo.processInfo.operatingSystemVersion
        let strVers = "\(vers.majorVersion).\(vers.minorVersion).\(vers.patchVersion)"
        
        // Hack for build number (only available via Apple private API, which will cause App Store rejection)
        var buildStr:String?
        let fullVersion = ProcessInfo.processInfo.operatingSystemVersionString
        if let buildStrCheck = fullVersion.components(separatedBy: " ").last?.dropLast() {
            buildStr = String(buildStrCheck)
        }
        
        var type:String?
#if os(macOS)
        type = "macOS"
#elseif os(iOS)
        type = "iOS"
#endif
        return (type, strVers, buildStr)
    }
}
