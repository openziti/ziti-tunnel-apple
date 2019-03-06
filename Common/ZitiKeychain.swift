//
//  ZitiKeychain.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/26/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiKeychain : NSObject {
    // kSecAttrAccessGroup not needed if sharing only a single keychain group.. 
    static let ZITI_KEYCHAIN_GROUP = "TEAMID.ZitiKeychain"
    var keySize = 2048
    let zid:ZitiIdentity
    
    init(_ zid:ZitiIdentity) {
        self.zid = zid
        super.init()
    }
    
    func createKeyPair() -> (privKey:SecKey?, pubKey:SecKey?, ZitiError?) {
        guard let atag = zid.id.data(using: .utf8) else {
            return (nil, nil, ZitiError("createPrivateKey: Unable to create application tag \(zid.id)"))
        }
        let privateKeyParams: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: atag]
        let publicKeyParams: [CFString: Any] = [
            kSecAttrIsPermanent: true as AnyObject,
            kSecAttrApplicationTag: atag]
        let parameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: keySize,
            kSecReturnRef: kCFBooleanTrue,
            kSecAttrIsPermanent: true, // macOs
            kSecAttrApplicationTag: atag, //macOs
            kSecPublicKeyAttrs: publicKeyParams,
            kSecPrivateKeyAttrs: privateKeyParams]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
            return (nil, nil, ZitiError("createKeyPair: Unable to create private key for \(zid.id): \(error!.takeRetainedValue() as Error)"))
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return (nil, nil, ZitiError("createKeyPair: Unable to copy public key for \(zid.id)"))
        }
        return (privateKey, publicKey, nil)
    }
 
    func getKeyPair() -> (privKey:SecKey?, pubKey:SecKey?, ZitiError?) {
        guard let atag = zid.id.data(using: .utf8) else {
            return (nil, nil, ZitiError("geKeyPair: Unable to create application tag \(zid.id)"))
        }
        let parameters:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecReturnRef: kCFBooleanTrue]
        var ref: AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &ref)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, nil, ZitiError("geKeyPair: Unable to get private key for \(zid.id): \(errStr)"))
        }
        let privKey = ref! as! SecKey
        guard let pubKey = SecKeyCopyPublicKey(privKey) else {
            return (nil, nil, ZitiError("geKeyPair: Unable to copy public key for \(zid.id)"))
        }
        return (privKey, pubKey, nil)
    }
    
    func keyPairExists() -> Bool {
        let (_, _, e) = getKeyPair()
        return e == nil
    }
    
    func deleteKeyPair() -> ZitiError? {
        guard let atag = zid.id.data(using: .utf8) else {
            return ZitiError("deleteKeyPair: Unable to create application tag \(zid.id)")
        }
        let deleteQuery:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: atag]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return ZitiError("Unable to delete key pair for \(zid.id): \(errStr)")
        }
        return nil
    }
    
    func getSecureIdentity() -> (SecIdentity?, ZitiError?) {
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue,
            kSecAttrLabel: zid.id]
        
        var cert: CFTypeRef?
        let certStatus = SecItemCopyMatching(params as CFDictionary, &cert)
        guard certStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(certStatus, nil) as String? ?? "\(certStatus)"
            return (nil, ZitiError("Unable to get certificate for \(zid.id): \(errStr)"))
        }
        
        let certificate = cert as! SecCertificate
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)  // TODO: macos only
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, ZitiError("Unable to get identity for \(zid.id): \(errStr)"))
        }
        return (identity, nil)
    }
    
    func storeCertificate(_ der:Data) -> ZitiError? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return ZitiError("Unable to create certificate from data for \(zid.id)")
        }
        let parameters: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: zid.id]
        let status = SecItemAdd(parameters as CFDictionary, nil)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return ZitiError("Unable to store certificate for \(zid.id): \(errStr)")
        }
        return nil
    }
    
    func getCertificate() -> (Data?, ZitiError?) {
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue,
            kSecAttrLabel: zid.id]
        
        var cert: CFTypeRef?
        let status = SecItemCopyMatching(params as CFDictionary, &cert)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, ZitiError("Unable to get certificate for \(zid.id): \(errStr)"))
        }
        guard let certData = SecCertificateCopyData(cert as! SecCertificate) as Data? else {
            return (nil, ZitiError("Unable to copy certificate data for \(zid.id)"))
        }
        return (certData, nil)
    }
    
    func deleteCertificate() -> ZitiError? {
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue,
            kSecAttrLabel: zid.id]
        
        var cert: CFTypeRef?
        let copyStatus = SecItemCopyMatching(params as CFDictionary, &cert)
        guard copyStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(copyStatus, nil) as String? ?? "\(copyStatus)"
            return ZitiError("Unable to find certificate for \(zid.id): \(errStr)")
        }
        
        let deleteStatus = SecKeychainItemDelete(cert as! SecKeychainItem) // TODO macos only
        guard deleteStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(deleteStatus, nil) as String? ?? "\(deleteStatus)"
            return ZitiError("Unable to delete certificate for \(zid.id): \(errStr)")
        }
        return nil
    }
    
    func convertToPEM(_ type:String, der:Data) -> String {
        guard let str = der.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)).addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            return ""
        }
        var pem = "-----BEGIN \(type)-----\n";
        for (i, ch) in str.enumerated() {
            pem.append(ch)
            if ((i != 0) && ((i+1) % 64 == 0)) {
                pem.append("\n")
            }
        }
        if (str.count % 64) != 0 {
            pem.append("\n")
        }
        return pem + "-----END \(type)-----\n"
    }
    
    func convertToDER(_ pem:String) -> Data {
        var der = Data()
        pem.split(separator: "\n").forEach { line in
            if line.starts(with: "-----") == false {
                der.append(Data(base64Encoded: String(line)) ?? Data())
            }
        }
        return der
    }
}
