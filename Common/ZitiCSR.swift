//
//  ZitiCSR.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/25/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation
import CommonCrypto

class ZitiCSR : NSObject {
    private let OBJECT_commonName:[UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
    private let OBJECT_countryName:[UInt8] = [0x06, 0x03, 0x55, 0x04, 0x06]
    private let OBJECT_organizationName:[UInt8] = [0x06, 0x03, 0x55, 0x04, 0x0A]
    private let SEQUENCE_tag:UInt8 = 0x30
    private let SET_tag:UInt8 = 0x31
    
    private let OBJECT_rsaEncryption:[UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
    let SEQUENCE_OBJECT_sha256WithRSAEncryption:[UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 1, 1, 0x0B, 0x05, 0x00]
    
    var country = "US"
    var org = "NetFoundry"
    var commonName = ""
    
    init(_ cn:String) {
        super.init()
        commonName = cn
    }
    
    func createRequest(_ zkc:ZitiKeychain) -> Data? {
        guard let privateKey = zkc.getPrivateKey() else {
            NSLog("ZitiCSR createRequest unable to get private key for \(zkc.zid.name): \(zkc.zid.id)")
            return nil
        }
        
        guard let publicKeyInfo = buildPublicKeyInfo(zkc) else {
            NSLog("ZitiCSR createRequest unable to build public key info for \(zkc.zid.name): \(zkc.zid.id)")
            return nil
        }
        
        // certificate request info
        var csr = Data()
        let version: [UInt8] = [0x02, 0x01, 0x00] // version 0
        csr.append(version, count: version.count)
        
        var subject = Data()
        appendSubjectItem(OBJECT_countryName, value: country, to: &subject)
        appendSubjectItem(OBJECT_organizationName, value: org, to: &subject)
        appendSubjectItem(OBJECT_commonName, value: commonName, to: &subject)
        subject.insert(contentsOf: [SEQUENCE_tag] + getDERLength(subject.count), at: 0)
        csr.append(subject)
        csr.append(publicKeyInfo)
        csr.append(contentsOf: [0xA0, 0x00]) // Attributes
        csr.insert(contentsOf: [SEQUENCE_tag] + getDERLength(csr.count), at: 0)
        
        // hash and sign
        var error: Unmanaged<CFError>?
        guard let sigData = createCriSignature(privateKey, csr, &error) else {
            NSLog("Unable to sign cert for \(zkc.zid.name): \(zkc.zid.id).  Error=\(error!.takeRetainedValue() as Error)")
            return nil
        }
        
        // append the sig
        let shaBytes = SEQUENCE_OBJECT_sha256WithRSAEncryption
        csr.append(shaBytes, count: shaBytes.count)
        
        var signData = Data([0x00]) // Prepend 0
        signData.append(sigData as Data)
        appendBITSTRING(signData, to: &csr)
        
        csr.insert(contentsOf: [SEQUENCE_tag] + getDERLength(csr.count), at: 0)
        return csr
    }
    
    func createCriSignature(_ privateKey:SecKey, _ cri:Data, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFData? {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        var SHA1 = CC_SHA256_CTX()
        CC_SHA256_Init(&SHA1)
        CC_SHA256_Update(&SHA1, [UInt8](cri), CC_LONG(cri.count))
        CC_SHA256_Final(&digest, &SHA1)
        
        var error: Unmanaged<CFError>?
        return SecKeyCreateSignature(
            privateKey, .rsaSignatureDigestPKCS1v15SHA256,
            Data(bytes: digest) as CFData, &error)
    }
    
    func parsePublicSecKey(publicKey: SecKey) -> (mod: Data, exp: Data) {
        let pubAttributes = SecKeyCopyAttributes(publicKey) as! [CFString:Any]
        
        let pubData  = pubAttributes[kSecValueData] as! Data
        let keySize  = pubAttributes[kSecAttrKeySizeInBits] as! Int
        var modulus  = pubData.subdata(in: 8..<(pubData.count - 5))
        let exponent = pubData.subdata(in: (pubData.count - 3)..<pubData.count) // correct
        
        modulus.removeFirst((modulus.count - (keySize/8))-1)
        if [UInt8](modulus)[0] != 0x00 {
            modulus.removeFirst(1)
        }
        return (mod: modulus, exp: exponent)
    }
    
    private func buildPublicKeyInfo(_ zkc:ZitiKeychain) -> Data? {
        guard let publicKey = zkc.getPublicKey() else {
            return nil
        }
        
        var publicKeyInfo = Data(OBJECT_rsaEncryption)
        publicKeyInfo.insert(contentsOf: [SEQUENCE_tag] + getDERLength(publicKeyInfo.count), at: 0)
        
        let (mod, exp) = parsePublicSecKey(publicKey: publicKey)
        var publicKeyASN = Data([0x02]) //  Integer
        publicKeyASN.append(contentsOf: getDERLength(mod.count))
        publicKeyASN.append(mod)
        publicKeyASN.append(UInt8(0x02)) // Integer
        publicKeyASN.append(contentsOf: getDERLength(exp.count))
        publicKeyASN.append(exp)
        
        publicKeyASN.insert(contentsOf: [0x00] + [SEQUENCE_tag] + getDERLength(publicKeyASN.count), at: 0)
        appendBITSTRING(publicKeyASN, to: &publicKeyInfo)
        publicKeyInfo.insert(contentsOf: [SEQUENCE_tag] + getDERLength(publicKeyInfo.count), at: 0)
        
        return publicKeyInfo
    }
    
    private func appendSubjectItem(_ what:[UInt8], value:String, to: inout Data) {
        var subjectItem = Data(what)
        appendUTF8String(string: value, to: &subjectItem)
        subjectItem.insert(contentsOf: [SEQUENCE_tag] + getDERLength(subjectItem.count), at: 0)
        subjectItem.insert(contentsOf: [SET_tag] + getDERLength(subjectItem.count), at: 0)
        to.append(subjectItem)
    }
    
    private func appendUTF8String(string: String, to: inout Data) ->(){
        let strType:UInt8 = 0x0C //UTF8STRING
        to.append(strType)
        to.append(contentsOf: getDERLength(string.lengthOfBytes(using: String.Encoding.utf8)))
        to.append(string.data(using: String.Encoding.utf8)!)
    }
    
    private func getDERLength(_ length:Int) -> [UInt8] {
        var derLength:[UInt8] = []
        if length < 128 {
            derLength = [UInt8(length)]
        } else if (length < 0x100) {
            derLength = [0x81, UInt8(length & 0xFF)]
        } else if length < 0x8000 {
            derLength = [0x82, UInt8((UInt(length & 0xFF00)) >> 8), UInt8(length & 0xFF)]
        }
        return derLength
    }
    
    private func appendBITSTRING(_ data: Data, to: inout Data) {
        to.append(0x03) //BIT STRING
        to.append(contentsOf: getDERLength(data.count))
        to.append(data)
    }
}
