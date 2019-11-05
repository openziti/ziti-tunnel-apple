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
        
        // make sure we have an id
        if zid.identity?.id == nil {
            guard let sub = zid.sub else {
                throw ZitiError("Unable to determine identity from JWT")
            }
            zid.identity = ZitiIdentity.Identity(zid.identity?.name ?? "-", sub)
        }
        
        // TODO: kickoff a request to get the controller version...
        
        // only support OTT
        guard zid.getEnrollmentMethod() == .ott else {
            throw ZitiError("Only OTT Enrollment is supported by this application")
        }
        
        // alread have this one?
        guard zids.first(where:{$0.id == zid.id}) == nil else {
            throw ZitiError("Duplicate Identity Not Allowed. Identy \(zid.name) is already present with id \(zid.id)")
        }
        
        // URL used to retrieve leaf public key
        guard let url = URL(string: "/version", relativeTo:URL(string:zid.getBaseUrl())) else {
        //guard let url = URL(string: zid.getBaseUrl()) else {
            throw ZitiError("Enable to convert URL for \"\(zid.getBaseUrl())\"")
        }
        
        // make sure we have a sig
        guard let signature = jwt.signature else {
            throw ZitiError("JWT signature not found")
        }
        
        let jwtAlg = jwt.header["alg"] as? String ?? "unspecified"
        var secKeyAlg:SecKeyAlgorithm
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
        
        // get dataToSign and decoded signature
        let comps = token.components(separatedBy: ".") // JWTDecode already guarentess we have 3 parts, no need to guard
        guard let signedData = (comps[0] + "." + comps[1]).data(using: .ascii) else {
            throw ZitiError("Unable to extract signing data")
        }
        guard let signedHashBytes = base64UrlDecode(signature) else {
            throw ZitiError("Unable to decode JWT signature")
        }
        
        // Can we get the public key?
        guard let pubKey = getPubKey(zid, url) else {
            throw ZitiError("JWT Unable to retrieve \(zid.getBaseUrl()) public key")
        }
        
        //var cfErr:CFError?
        if !SecKeyVerifySignature(pubKey, secKeyAlg, signedData as CFData, signedHashBytes as CFData, nil) {
            throw ZitiError("Unable to verify JWT sig, alg=\(jwtAlg)")
        }
        
        // store it
        if let error = zidStore.store(zid) { throw error }
        
        // add it
        zids.insert(zid, at:at)
    }
    
    private func getPubKey(_ zid:ZitiIdentity, _ url:URL) -> SecKey? {
        let jwtScraper = JwtPubKeyScraper()
        jwtScraper.zid = zid
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate:jwtScraper, delegateQueue:nil)
        session.dataTask(with: url) { (data, response, error) in
            if let data = data,
                let json = ((try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]) as [String : Any]??),
                let dataJSON = json?["data"] as? [String: Any],
                let version = dataJSON["version"] as? String
            {
                NSLog("\(zid.id) controller version: \(version) (\(url.absoluteString))")
                zid.controllerVersion = version
            }
        }.resume() // signals when key retrieved by delegate
        session.finishTasksAndInvalidate()
        
        if !jwtScraper.wait(5.0) {
            NSLog("JWT timed out waiting for server \(url.absoluteString) public key")
            return nil
        }
        
        guard let pubKey = jwtScraper.jwtPubKey else {
            NSLog("JWT Unable to retrieve \(url.absoluteString) public key")
            return nil
        }
        return pubKey
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
    var zid:ZitiIdentity?
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
            
            // Store off the key so we can validate the JWT sig
            self?.jwtPubKey = SecTrustCopyPublicKey(secTrust)
            self?.jwtPubKeyCond.lock()
            self?.jwtPubKeyCond.signal()
            self?.jwtPubKeyCond.unlock()
            
            // Temp workaround until implement fetching certs per RFC7030
            guard let zid = self?.zid else { return }
            if zid.rootCa == nil {
                var newRootCa:String = ""
                let zkc = ZitiKeychain()
                for i in 0..<SecTrustGetCertificateCount(secTrust) {
                    if let cert = SecTrustGetCertificateAtIndex(secTrust, i) {
                        let summary = SecCertificateCopySubjectSummary(cert)
                        print("Cert summary: \(summary ?? "No summary available" as CFString)")
                        
                        if let certData = SecCertificateCopyData(cert) as Data? {
                            newRootCa += zkc.convertToPEM("CERTIFICATE", der: certData)
                        }
                    }
                }
                if newRootCa.count > 0 {
                    self?.zid?.rootCa = newRootCa
                }
            }
            completionHandler(.useCredential, URLCredential(trust:secTrust))
        }
        
        if steStatus != errSecSuccess {
            NSLog("JWT Unable to evaluate server trust")
            jwtPubKeyCond.lock()
            jwtPubKeyCond.signal()
            jwtPubKeyCond.unlock()
            return completionHandler(.performDefaultHandling, nil)
        }
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
