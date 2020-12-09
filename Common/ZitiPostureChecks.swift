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
// import ZitiPosture
import AppKit
import CryptoKit
import CommonCrypto
#endif

class ZitiPostureChecks : CZiti.ZitiPostureChecks {
    var type:String?, strVers:String?, buildStr:String?
    
    #if os(macOS)
    //let service:ZitiPostureProtocol?
    #endif
    
    override init() {
        // just get these once...
        (type, strVers, buildStr) = ZitiPostureChecks.getOsInfo()
/*
#if os(macOS)
        // setup XPC
        let connection = NSXPCConnection(serviceName: "io.netfoundry.ZitiPacketTunnel.ZitiPosture")
        connection.remoteObjectInterface = NSXPCInterface(with: ZitiPostureProtocol.self)
        connection.resume()

        service = connection.remoteObjectProxyWithErrorHandler { error in
            zLog.error("Received error getting proxy for ZitPosture XPC Service: \(error)")
        } as? ZitiPostureProtocol
#endif
*/
        
        super.init()
        self.macQuery = macQueryImpl
        self.processQuery = processQueryImpl
        self.domainQuery = domainQueryImpl
        self.osQuery = osQueryImpl
        
        Thread(target: self, selector: #selector(keepAlive), object: nil).start()
    }
    
    // NSWorkspace runningApplications need main runloop to be active or list of processes doesn't get updated...
    @objc func keepAlive() {
        let t = Timer(fire: Date(), interval: 10, repeats: true) {_ in }
        RunLoop.main.add(t, forMode: .common)
        RunLoop.main.run()
    }
    
    
    func macQueryImpl(_ ctx:ZitiPostureContext, _ cb: @escaping MacResponse) {
        autoreleasepool { // implicit closure from init()
            // these can be changed without rebooting, so get them every time...
            let macAddrs = ZitiPostureChecks.getMacAddrs()
            zLog.debug("MAC Posture Response: \(String(describing: macAddrs))")
            cb(ctx, macAddrs)
        }
    }
    
    func processQueryImpl(_ ctx:ZitiPostureContext, _ path:String, _ cb: @escaping ProcessResponse) {
        autoreleasepool {
#if os(macOS)
            /*guard let service = service else {
                zLog.error("ZitiPosture XPC Servicex not available.")
                cb(ctx, path, false, nil, nil)
                return
            }
            service.processQuery(path) { isRunning, hashString, signers in
                zLog.debug("Process Posture Response: path=\(path), isRunning=\(isRunning), hash=\(hashString ?? "nil"), signers=\(signers ?? [])")
                cb(ctx, path, isRunning, hashString, signers)
            }*/
            let isRunning = checkIfRunning(path)
            let url = URL(fileURLWithPath: path)
            var hashString:String?

            if let data = try? Data(contentsOf: url) {
                let hashed = SHA512.hash(data: data)
                hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
            }
            
            let signers = getSigners(url)
            zLog.debug("Process Posture Response: path=\(path), isRunning=\(isRunning), hash=\(hashString ?? "nil"), signers=\(signers ?? [])")
            cb(ctx, path, isRunning, hashString, signers)
#else
            cb(ctx, path, false, nil, nil)
#endif
        }
    }
    
    func domainQueryImpl(_ ctx:ZitiPostureContext, _ cb: @escaping DomainResponse) {
        autoreleasepool { // implicit closure from init()
            zLog.warn("Domain Posture Query - Unimplemented")
            cb(ctx, nil)
        }
    }
    
    func osQueryImpl(_ ctx:ZitiPostureContext, _ cb: @escaping OsResponse) {
        autoreleasepool { // implicit closure from init()
            zLog.debug("OS Posture Response: type=\(type ?? "nil"), vers=\(strVers ?? ""), build=\(buildStr ?? "")")
            cb(ctx, type, strVers, buildStr)
        }
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
    
#if os(macOS)
    func checkIfRunning(_ path:String) -> Bool {
        var found = false
        for app in NSWorkspace.shared.runningApplications {
            if let exePath = app.executableURL?.path, FileManager.default.contentsEqual(atPath: exePath, andPath: path) {
                found = !app.isTerminated
                break
            }
        }
        return found
    }

    func getSigners(_ url:URL) -> [String]? {
        var signers:[String]?
        
        var codeRef:SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &codeRef)
        guard createStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(createStatus, nil) as String? ?? "\(createStatus)"
            zLog.error("Unable to create static code object for file \"\(url.path)\": \(errStr)")
            return nil
        }

        var cfDict:CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(codeRef!, SecCSFlags(rawValue: kSecCSSigningInformation), &cfDict)
        guard copyStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(createStatus, nil) as String? ?? "\(copyStatus)"
            zLog.error("Unable to retrieve signining info for file \"\(url.path)\": \(errStr)")
            return nil
        }

        if let dict = cfDict as? [CFString:AnyObject] {
            if dict[kSecCodeInfoCertificates] != nil {
                let certChain = dict[kSecCodeInfoCertificates] as? [SecCertificate]
                certChain?.forEach { cert in
                    let der = SecCertificateCopyData(cert) as Data
                    var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
                    der.withUnsafeBytes {
                        _ = CC_SHA1($0.baseAddress, CC_LONG(der.count), &digest)
                    }
                    let hexStr = digest.map { String(format: "%02x", $0) }.joined()
                    if signers == nil { signers = [] }
                    signers?.append(hexStr)
                }
            }
        }
        return signers
    }
#endif
}
