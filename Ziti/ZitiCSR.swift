//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import CommonCrypto

class ZitiCSR : NSObject {
    private let COMMON_NAME:[UInt8]  = [0x06, 0x03, 0x55, 0x04, 0x03]
    private let ORG_NAME:[UInt8]     = [0x06, 0x03, 0x55, 0x04, 0x0A]
    private let COUNTRY_NAME:[UInt8] = [0x06, 0x03, 0x55, 0x04, 0x06]
    private let SEQUENCE_tag:UInt8 = 0x30
    private let SET_tag:UInt8 = 0x31
    private let INTEGER_tag:UInt8 = 0x02
    private let UTF8STRING_tag:UInt8 = 0x0C
    private let BITSTRING_tag:UInt8 = 0x03
    private let RSA_NULL:[UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
    
    // including sequence tag and size
    let SHA256_WITH_RSA:[UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 1, 1, 0x0B, 0x05, 0x00]
    
    var country = "US"
    var org = "NetFoundry"
    var commonName = ""
    
    init(_ cn:String) {
        super.init()
        commonName = cn
    }
    
    func createRequest(privKey:SecKey, pubKey:SecKey) -> (Data?, ZitiError?) {
        var csr = Data()
        let version: [UInt8] = [0x02, 0x01, 0x00] // version 0
        csr.append(version, count: version.count)
        
        var subject = Data()
        appendSubjectItem(COUNTRY_NAME, value: country, to: &subject)
        appendSubjectItem(ORG_NAME, value: org, to: &subject)
        appendSubjectItem(COMMON_NAME, value: commonName, to: &subject)
        subject.insert(contentsOf: [SEQUENCE_tag] + getDERLength(subject.count), at: 0)
        csr.append(subject)
        csr.append(buildPublicKeyInfo(publicKey:pubKey))
        csr.append(contentsOf: [0xA0, 0x00]) // Attributes
        csr.insert(contentsOf: [SEQUENCE_tag] + getDERLength(csr.count), at: 0)
        
        // hash and sign
        var err: Unmanaged<CFError>?
        guard let sigData = createCriSig(privKey, csr, &err) else {
            return (nil, ZitiError("Unable to sign cert for \(commonName): \(err!.takeRetainedValue() as Error)"))
        }
        
        // append the sig
        csr.append(contentsOf: SHA256_WITH_RSA)
        let bitstring = Data([0x00] + [UInt8](sigData as Data))
        csr.append(contentsOf: [BITSTRING_tag] + getDERLength(bitstring.count) + bitstring)
        csr.insert(contentsOf: [SEQUENCE_tag] + getDERLength(csr.count), at: 0)
        return (csr, nil)
    }
    
    private func createCriSig(_ privKey:SecKey, _ cri:Data, _ err: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFData? {
        var md = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        var ctx = CC_SHA256_CTX()
        
        CC_SHA256_Init(&ctx)
        CC_SHA256_Update(&ctx, [UInt8](cri), CC_LONG(cri.count))
        CC_SHA256_Final(&md, &ctx)
        return SecKeyCreateSignature(
            privKey, .rsaSignatureDigestPKCS1v15SHA256,
            Data(md) as CFData, err)
    }
    
    private func parsePublicSecKey(publicKey: SecKey) -> (mod: Data, exp: Data) {
        let pubAttributes = SecKeyCopyAttributes(publicKey) as! [CFString:Any]
        let pubData  = pubAttributes[kSecValueData] as! Data
        let keySize  = pubAttributes[kSecAttrKeySizeInBits] as! Int
        let exponent = pubData.subdata(in: (pubData.count - 3)..<pubData.count)
        var modulus  = pubData.subdata(in: 0..<(pubData.count - 5)) 
        
        modulus.removeFirst(modulus.count - (keySize/8))
        let msByte = [UInt8](modulus)[0]  // if msBit isn't 0, insert a zero byte
        if (msByte != 0x00) && (msByte > 0x7f) {
            modulus.insert(0x00, at: modulus.startIndex)
        }
        return (mod: modulus, exp: exponent)
    }
    
    private func buildPublicKeyInfo(publicKey:SecKey) -> Data {
        var publicKeyInfo = Data(RSA_NULL)
        publicKeyInfo.insert(contentsOf: [SEQUENCE_tag] + getDERLength(publicKeyInfo.count), at: 0)
        
        let (mod, exp) = parsePublicSecKey(publicKey: publicKey)
        var publicKeyASN = Data([INTEGER_tag])
        publicKeyASN.append(contentsOf: getDERLength(mod.count))
        publicKeyASN.append(mod)
        publicKeyASN.append(INTEGER_tag)
        publicKeyASN.append(contentsOf: getDERLength(exp.count))
        publicKeyASN.append(exp)
        
        publicKeyASN.insert(contentsOf: [0x00] + [SEQUENCE_tag] + getDERLength(publicKeyASN.count), at: 0)
        publicKeyInfo.append(contentsOf: [BITSTRING_tag] + getDERLength(publicKeyASN.count) + publicKeyASN)
        publicKeyInfo.insert(contentsOf: [SEQUENCE_tag] + getDERLength(publicKeyInfo.count), at: 0)
        
        return publicKeyInfo
    }
    
    private func appendSubjectItem(_ what:[UInt8], value:String, to: inout Data) {
        var subjectItem = Data(what)
        subjectItem.append(contentsOf: [UTF8STRING_tag] +
            getDERLength(value.lengthOfBytes(using: String.Encoding.utf8)) +
            value.data(using: String.Encoding.utf8)!)
        subjectItem.insert(contentsOf: [SEQUENCE_tag] + getDERLength(subjectItem.count), at: 0)
        subjectItem.insert(contentsOf: [SET_tag] + getDERLength(subjectItem.count), at: 0)
        to.append(subjectItem)
    }
    
    private func getDERLength(_ length:Int) -> [UInt8] {
        var derLength:[UInt8] = []
        if length < 0x80 {
            derLength = [UInt8(length)]
        } else if (length < 0x100) {
            derLength = [0x81, UInt8(length & 0xFF)]
        } else if length < 0x8000 {
            derLength = [0x82, UInt8((UInt(length & 0xFF00)) >> 8), UInt8(length & 0xFF)]
        }
        return derLength
    }
}
