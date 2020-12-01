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
import CryptoKit
import CommonCrypto

class ZitiPosture: NSObject, ZitiPostureProtocol {
    override init() {
        Logger.initShared(Logger.TUN_TAG)
        super.init()
    }
    
    func upperCaseString(_ string: String, withReply reply: @escaping (String) -> Void) {
        let response = string.uppercased()
        reply(response)
    }
    
    func processQuery(_ path:String, withReply reply: @escaping (_ isRunning:Bool,_  sha512Hash:String?, _ signers:[String]?) -> Void) {
        let isRunning = is_running(path.cString(using: .utf8))
        let url = URL(fileURLWithPath: path)
        var hashString:String?

        if let data = try? Data(contentsOf: url) {
            let hashed = SHA512.hash(data: data)
            hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        }
        let signers = getSigners(url)
        reply(isRunning, hashString, signers)
    }
    
    func getSigners(_ url:URL) -> [String]? {
        var signers:[String]?
        
        var codeRef:SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &codeRef)
        guard createStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(createStatus, nil) as String? ?? "\(createStatus)"
            NSLog("Unable to create static code object for file \"\(url.path)\": \(errStr)")
            return nil
        }

        var cfDict:CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(codeRef!, SecCSFlags(rawValue: kSecCSSigningInformation), &cfDict)
        guard copyStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(createStatus, nil) as String? ?? "\(copyStatus)"
            NSLog("Unable to retrieve signining info for file \"\(url.path)\": \(errStr)")
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
}
