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
import CryptoKit
#if os(macOS)
import AppKit
#endif

class ZitiPostureChecks : CZiti.ZitiPostureChecks {
    override init() {
        super.init()
        self.macQuery = macQueryImpl
        self.processQuery = processQueryImpl
        self.domainQuery = domainQueryImpl
        self.osQuery = osQueryImpl
    }
    
    let macQueryImpl:MacQuery = { ctx, cb in
        var strs:[String]?
        let addrs = get_mac_addrs();
        if var ptr = addrs {
            strs = []
            while let s = ptr.pointee {
                strs?.append(String(cString:s))
                ptr += 1
            }
        }
        free_mac_addrs(addrs)
        NSLog("MAC Posture Response: \(String(describing: strs))")
        cb(ctx, strs)
        
    }
    
    let processQueryImpl:ProcessQuery = { ctx, path, cb in
        #if os(macOS)
        let isRunning = checkIfRunning(path)
        
        var hashString:String?
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let hashed = SHA512.hash(data: data)
            hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        }
        NSLog("Process Posture Response: path=\(path), isRunning=\(isRunning), hash=\(hashString ?? "nil")")
        cb(ctx, path, isRunning, hashString, nil) // TODO: signers
        #else
        cb(ctx, path, false, nil, nil)
        #endif
    }
    
    let domainQueryImpl:DomainQuery = { ctx, cb in
        NSLog("Domain Posture Query - Unimplemented")
        cb(ctx, nil)
    }
    
    let osQueryImpl:OsQuery = { ctx, cb in
        let vers = ProcessInfo.processInfo.operatingSystemVersion
        let strVers = "\(vers.majorVersion).\(vers.minorVersion)" // ".\(vers.patchVersion)" // TODO: see what needs to happen to add patchVersion...
        
        var type:String?
#if os(macOS)
        type = "macOS"
#elseif os(iOS)
        type = "iOS"
#endif
        NSLog("OS Posture Response: type=\(type ?? "nil"), vers=\(strVers)")
        cb(ctx, type, strVers, nil)
    }
}

#if os(macOS)
func checkIfRunning(_ path:String) -> Bool {
    var found = false
    for app in NSWorkspace.shared.runningApplications {
        // contentsEqualAt correct?  more expensive than stright string comparison...
        if let exePath = app.executableURL?.path, FileManager.default.contentsEqual(atPath: exePath, andPath: path) {
            NSLog("Found running app for \"\(path)\"\n   name: \(String(describing: app.localizedName))\n   bundleId: \(app.bundleIdentifier ?? "")\n   bundlePath:\(app.bundleURL?.path ?? "")")
            found = true
            break
        }
    }
    return found
}
#endif
