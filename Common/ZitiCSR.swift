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
    var org = "Netfoundry" // grrr on lowercase f
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
        var cri = Data()
        let version: [UInt8] = [0x02, 0x01, 0x00] // version 0
        cri.append(version, count: version.count)
        
        var subject = Data()
        appendSubjectItem(OBJECT_countryName, value: country, into: &subject)
        appendSubjectItem(OBJECT_organizationName, value: org, into: &subject)
        appendSubjectItem(OBJECT_commonName, value: commonName, into: &subject)
        enclose(&subject, by: SEQUENCE_tag)
        cri.append(subject)
        cri.append(publicKeyInfo)
        cri.append(contentsOf: [0xA0, 0x00]) // Attributes
        enclose(&cri, by: SEQUENCE_tag)
        
        // Hash and sign
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        var SHA1 = CC_SHA256_CTX()
        CC_SHA256_Init(&SHA1)
        CC_SHA256_Update(&SHA1, [UInt8](cri), CC_LONG(cri.count))
        CC_SHA256_Final(&digest, &SHA1)
        
        var error: Unmanaged<CFError>?
        guard let sigData = SecKeyCreateSignature(
            privateKey, .rsaSignatureDigestPKCS1v15SHA256,
            Data(bytes: digest) as CFData, &error) else {
            NSLog("Unable to sign cert for \(zkc.zid.name): \(zkc.zid.id).  Error=\(error!.takeRetainedValue() as Error)")
            return nil
        }
        
        var csr = Data()
        csr.append(cri)
        
        let shaBytes = SEQUENCE_OBJECT_sha256WithRSAEncryption
        csr.append(shaBytes, count: shaBytes.count)
        
        var signData = Data(bytes: [0x00]) // Prepend 0
        signData.append(sigData as Data)
        appendBITSTRING(signData, into: &csr)
        
        enclose(&csr, by: SEQUENCE_tag) // Enclose into SEQUENCE
        return csr
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
        
        var publicKeyInfo = Data()
        publicKeyInfo.append(contentsOf: OBJECT_rsaEncryption)
        enclose(&publicKeyInfo, by: SEQUENCE_tag) // Enclose into SEQUENCE
        
        var publicKeyASN = Data()
        let (mod, exp) = parsePublicSecKey(publicKey: publicKey)
        publicKeyASN.append(UInt8(0x02)) // Integer
        appendDERLength(mod.count, into: &publicKeyASN)
        publicKeyASN.append(mod)
        
        publicKeyASN.append(UInt8(0x02)) // Integer
        appendDERLength(exp.count, into: &publicKeyASN)
        publicKeyASN.append(exp)
        
        enclose(&publicKeyASN, by: SEQUENCE_tag)
 
        prependByte(0x00, into: &publicKeyASN) //Prepend 0 (?)
        appendBITSTRING(publicKeyASN, into: &publicKeyInfo)
        
        enclose(&publicKeyInfo, by: SEQUENCE_tag) // Enclose into SEQUENCE
        
        return publicKeyInfo
    }
    
    private func appendSubjectItem(_ what:[UInt8], value:String, into: inout Data) {
        var subjectItem = Data()
        subjectItem.append(contentsOf: what)
        appendUTF8String(string: value, into: &subjectItem)
        enclose(&subjectItem, by: SEQUENCE_tag)
        enclose(&subjectItem, by: SET_tag)
        into.append(subjectItem)
    }
    
    private func appendUTF8String(string: String, into: inout Data) ->(){
        let strType:UInt8 = 0x0C //UTF8STRING
        into.append(strType)
        appendDERLength(string.lengthOfBytes(using: String.Encoding.utf8), into: &into)
        into.append(string.data(using: String.Encoding.utf8)!)
    }
    
    private func enclose(_ data: inout Data, by:UInt8){
        var newData = Data()
        newData.append(by)
        appendDERLength(data.count, into: &newData)
        newData.append(data)
        data = newData
    }
    
    private func appendDERLength(_ length: Int, into: inout Data) {
        if length < 128 {
            into.append(UInt8(length))
        } else if (length < 0x100) {
            into.append(contentsOf: [0x81, UInt8(length & 0xFF)])
        } else if length < 0x8000{
            into.append(contentsOf: [0x82, UInt8((UInt(length & 0xFF00)) >> 8), UInt8(length & 0xFF)])
        }
    }
    
    private func prependByte(_ byte: UInt8, into: inout Data) {
        var newData = Data(capacity: into.count + 1)
        newData.append(byte)
        newData.append(into)
        into = newData
    }
    
    private func appendBITSTRING(_ data: Data, into: inout Data) {
        let strType:UInt8 = 0x03 //BIT STRING
        into.append(strType)
        appendDERLength(data.count, into: &into)
        into.append(data)
    }
}
