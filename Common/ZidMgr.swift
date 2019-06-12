//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import JWTDecode
import CommonCrypto

class ZidMgr : NSObject {
    var zids:[ZitiIdentity] = []
    var zidStore = ZitiIdentityStore()
    
    func loadZids() -> ZitiError? {
        let (zids, err) = zidStore.loadAll()
        guard err == nil else { return err }
        self.zids = zids ?? []
        return nil
    }
    
    func insertFromJWT(_ url:URL, at:Int) throws {
        let token = try String(contentsOf: url, encoding: .utf8)
        let jwt = try decode(jwt: token)
        
        // parse the body
        guard let data = try? JSONSerialization.data(withJSONObject:jwt.body),
            let zid = try? JSONDecoder().decode(ZitiIdentity.self, from: data)
            else {
                throw ZitiError("Unable to parse enrollment data")
        }
        
        // only support OTT
        guard zid.method == .ott else {
            throw ZitiError("Only OTT Enrollment is supported by this application")
        }
        
        // alread have this one?
        guard zids.first(where:{$0.id == zid.id}) == nil else {
            throw ZitiError("Duplicate Identity Not Allowed. Identy \(zid.name) is already present with id \(zid.id)")
        }
        
        // URL used to retrieve leaf public key
        guard let url = URL(string: zid.apiBaseUrl) else {
            throw ZitiError("Enable to convert URL for \"\(zid.apiBaseUrl)\"")
        }
        
        // make sure we have a sig
        guard let signature = jwt.signature else {
            throw ZitiError("JWT signature not found")
        }
        
        
        // Hit zid.apiBaseUrl and get public key from leaf cert (at index 0)
        let jwtScraper = JwtPubKeyScraper()
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate:jwtScraper, delegateQueue:nil)
        session.dataTask(with: url).resume() // signals when key retrieved
        session.finishTasksAndInvalidate()
        
        // Wait for public key to be scraped
        if !jwtScraper.wait(5.0) {
            throw ZitiError("JWT timed out waiting for server \(zid.apiBaseUrl) public key")
        }
        
        // Did we get the public key?
        guard let pubKey = jwtScraper.jwtPubKey else {
            throw ZitiError("JWT Unable to retrieve \(zid.apiBaseUrl) public key")
        }
        NSLog("JWT pub key: \(pubKey)")
        
        
        let jwtAlg = jwt.header["alg"] as? String ?? "unspecified"
        var secKeyAlg:SecKeyAlgorithm
        NSLog("JWT Alg: \(jwtAlg)")
        switch jwtAlg {
        case "RS256": secKeyAlg = .rsaSignatureMessagePKCS1v15SHA256
        case "RS384": secKeyAlg = .rsaSignatureMessagePKCS1v15SHA384
        case "RS512": secKeyAlg = .rsaSignatureMessagePKCS1v15SHA512
        case "ES256": secKeyAlg = .ecdsaSignatureMessageX962SHA256
        case "ES384": secKeyAlg = .ecdsaSignatureMessageX962SHA384
        case "ES512": secKeyAlg = .ecdsaSignatureMessageX962SHA512
        default:
            throw ZitiError("JWT unsupported signing algorythm \(jwtAlg)")
        }
        
        let comps = token.components(separatedBy: ".") // TODO: errorcheck for 3 parts
        let signedData = (comps[0] + "." + comps[1]).data(using: .ascii)
        
        let signedHashBytesSize = SecKeyGetBlockSize(pubKey)
        NSLog("JWT pub key size: \(signedHashBytesSize)")
        let signedHashBytes = base64UrlDecode(signature)
        
        //var cfErr:CFError?
        if !SecKeyVerifySignature(pubKey, secKeyAlg, signedData! as CFData, signedHashBytes! as CFData, nil) { // TODO Error check
            throw ZitiError("Unable to verify JWT sig, alg=\(jwtAlg)")
        }
        
        // store it
        if let error = zidStore.store(zid) {
            throw error
        }
        
        // add it
        zids.insert(zid, at:at)
    }
    
    private func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
}

class JwtPubKeyScraper : NSObject, URLSessionDelegate {
    var jwtPubKey:SecKey?
    let jwtPubKeyCond = NSCondition()
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return completionHandler(.performDefaultHandling, nil)
        }
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            NSLog("JWT ServerTrustChallenge: ServerTrust not available. Performming default handling.")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let steStatus = SecTrustEvaluateAsync(serverTrust, DispatchQueue(label: "ServerTrust")) { [weak self] secTrust, result in
            self?.jwtPubKey = SecTrustCopyPublicKey(secTrust)
            self?.jwtPubKeyCond.lock()
            self?.jwtPubKeyCond.signal()
            self?.jwtPubKeyCond.unlock()
        }
        
        if steStatus != errSecSuccess {
            NSLog("JWT Unable to evaluate server trust")
            jwtPubKeyCond.lock()
            jwtPubKeyCond.signal()
            jwtPubKeyCond.unlock()
        }
        
        return completionHandler(.performDefaultHandling, nil)
    }
    
    func wait(_ ti:TimeInterval) -> Bool {
        var timedOut = false
        jwtPubKeyCond.lock()
        while jwtPubKey == nil {
            if !jwtPubKeyCond.wait(until: Date(timeIntervalSinceNow: ti)) {
                timedOut = true
                break
            }
        }
        jwtPubKeyCond.unlock()
        return !timedOut
    }
}
