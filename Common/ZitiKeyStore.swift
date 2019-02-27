//
//  ZitiKeyStore.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 2/26/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiKeyStore : NSObject {
    // kSecAttrAccessGroup not needed if sharing only a single keychain group.. 
    static let ZITI_KEYCHAIN_GROUP = "TEAMID.ZitiKeyStore"
    var keySize = 1024
    let zid:ZitiIdentity
    
    init(_ zid:ZitiIdentity) {
        self.zid = zid
        super.init()
    }
    
    func createPrivateKey() -> SecKey? {
        guard let atag = zid.id.data(using: .utf8) else {
            return nil
        }
        
        let privateKeyParams: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: atag]
        
        let publicKeyParams: [CFString: Any] = [
            (kSecAttrIsPermanent): true as AnyObject,
            (kSecAttrApplicationTag): atag]
        
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
            NSLog("Error \(error!.takeRetainedValue() as Error) createSecureKeyPair for \(zid.name): \(zid.id)")
            return nil
        }
        return privateKey
    }
    
    func getPublicKeyData() -> Data? {
        guard let atag = zid.id.data(using: .utf8) else {
            return nil
        }
        
        let parameters:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrApplicationTag: atag,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecReturnData: kCFBooleanTrue]
        var data: AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &data)
        return status == errSecSuccess ? data as? Data : nil
    }
    
    func getPublicKey(_ zid:ZitiIdentity) -> SecKey? {
        guard let pk = getPrivateKey() else {
            return nil
        }
        return SecKeyCopyPublicKey(pk)
    }
    
    func getPrivateKey() -> SecKey? {
        guard let atag = zid.id.data(using: .utf8) else {
            return nil
        }
        
        let parameters:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecReturnRef: kCFBooleanTrue]
        var ref: AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &ref)
        return status == errSecSuccess ? ref as! SecKey? : nil
    }
    
    func keyPairExists() -> Bool {
        return self.getPublicKeyData() != nil
    }
    
    func deleteKeyPair() -> OSStatus {
        guard let atag = zid.id.data(using: .utf8) else {
            return errSecItemNotFound
        }
        let deleteQuery:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: atag,]
        return SecItemDelete(deleteQuery as CFDictionary)
    }
}
