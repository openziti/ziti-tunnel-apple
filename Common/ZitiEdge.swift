//
//  ZitiEdge.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/5/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

fileprivate let AUTH_PATH = "authenticate?method=cert"
fileprivate let SESSION_TAG = "zt-session"
fileprivate let SERVCES_PATH = "services"
fileprivate let GET_METHOD = "GET"
fileprivate let POST_METHOD = "POST"
fileprivate let CONTENT_TYPE = "Content-Type"
fileprivate let JSON_TYPE = "application/json; charset=utf-8"
fileprivate let TEXT_TYPE = "text/plain; charset=utf-8"
fileprivate let PEM_CERTIFICATE = "CERTIFICATE"
fileprivate let PEM_CERTIFICATE_REQUEST = "CERTIFICATE REQUEST"

class ZitiEdge : NSObject {
    
    let zid:ZitiIdentity
    var sessionToken:String? = nil
    
    init(_ zid:ZitiIdentity) {
        self.zid = zid
    }
    
    // looks like this is pointless? need to ask Andrew...
    func authenticate(completionHandler: @escaping (ZitiError?) -> Void) {
        let servicesStr = zid.apiBaseUrl + AUTH_PATH
        guard let url = URL(string: servicesStr) else {
            completionHandler(ZitiError("Enable to convert services URL \"\(servicesStr)\""))
            return
        }
        
        let (session, urlRequest) = getURLSession(
            url:url, method:POST_METHOD, contentType:JSON_TYPE, body:nil)
        
        session.dataTask(with: urlRequest) { (data, response, error) in
            if let zErr = self.validateResponse(data, response, error) {
                completionHandler(zErr)
                return
            }
            
            // Not worth making Codables for this...
            guard
                let json = try? JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any],
                let dataJSON = json?["data"] as? [String: Any],
                let sessionJSON = dataJSON["session"] as? [String:Any],
                let token = sessionJSON["token"] as? String
            else {
                    completionHandler(ZitiError("error trying to convert data to JSON"))
                    return
            }
            print("zt-session: \(token)")
            self.sessionToken = token
            completionHandler(nil)
        }.resume()
    }
    
    func enroll(completionHandler: @escaping (ZitiError?) -> Void) {
        // Got a URL?
        guard let url = URL(string: zid.enrollmentUrl) else {
            completionHandler(ZitiError("Enable to convert enrollment URL \"\(zid.enrollmentUrl)\""))
            return
        }
        
        // Get Keys
        let zkc = ZitiKeychain(zid)
        let (privKey, pubKey, keyErr) = getKeys(zkc)
        guard keyErr == nil else {
            completionHandler(keyErr)
            return
        }
        
        // Create CSR
        let zcsr = ZitiCSR(zid.id)
        let (csr, crErr) = zcsr.createRequest(privKey: privKey!, pubKey: pubKey!)
        guard crErr == nil else {
            completionHandler(crErr)
            return
        }
        
        // Submit CSR
        let csrPEM = zkc.convertToPEM(PEM_CERTIFICATE_REQUEST, der: csr!).data(using: String.Encoding.utf8)
        let (session, urlRequest) = getURLSession(
            url:url,
            method:POST_METHOD,
            contentType:TEXT_TYPE,
            body:csrPEM)
        
        session.dataTask(with: urlRequest) { (data, response, error) in
            if let zErr = self.validateResponse(data, response, error) {
                completionHandler(zErr)
                return
            }
            guard let certPEM = String(data: data!, encoding: .utf8) else {
                completionHandler(ZitiError("Unable to encode PEM data"))
                return
            }
            let certDER = zkc.convertToDER(certPEM)
            
            if let zStoreErr = zkc.storeCertificate(certDER) {
                completionHandler(zStoreErr)
                return
            }
            self.zid.enrolled = true
            completionHandler(nil)
        }.resume()
    }
    
    // TODO: getServices
    // TODO: getNetworkSession
    
    func handleServerTrustChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        // get server's CA
        guard let serverTrust = challenge.protectionSpace.serverTrust,
            let cert = SecTrustGetCertificateAtIndex(serverTrust, 0),
            let remoteCertData = CFBridgingRetain(SecCertificateCopyData(cert))
        else {
            print("... Could not get server cert!")
            completionHandler(.cancelAuthenticationChallenge, nil);
            return
        }
        
        // if we have .rootCA check if we match. Else rely on default handling
        guard let rootCaPEM = zid.rootCa else {
            print("...no rootCa for \(zid.name) - will perform default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let zkc = ZitiKeychain(zid)
        let localCertData = zkc.convertToDER(rootCaPEM)
        guard remoteCertData.isEqual(to: localCertData) == true else {
            print("... Certificates don't match!")
            completionHandler(.cancelAuthenticationChallenge, nil);
            return
        }
        
        // looks good
        print("...got a match for \(zid.name) - this should work :)")
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
    
    private func getURLSession(url:URL, method:String, contentType:String, body:Data?) -> (URLSession, URLRequest) {
        let session = URLSession(
            configuration: URLSessionConfiguration.default,
            delegate: self,
            delegateQueue:OperationQueue.main)
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue(contentType, forHTTPHeaderField: CONTENT_TYPE)
        if self.sessionToken != nil {
            urlRequest.setValue(self.sessionToken, forHTTPHeaderField: SESSION_TAG)
        }
        urlRequest.httpBody = body
        
        return (session, urlRequest)
    }
    
    private func validateResponse(_ data:Data?, _ response:URLResponse?, _ error:Error?) -> ZitiError? {
        guard error == nil,
            let httpResp = response as? HTTPURLResponse,
            let respData = data
        else {
            return ZitiError(error?.localizedDescription ??
                "Invalid or empty response from enrollment server")
        }
        
        guard httpResp.statusCode == 200 else {
            guard let edgeErrorResp = try? JSONDecoder().decode(ZitiEdgeErrorResponse.self, from: respData) else {
                let respStr = HTTPURLResponse.localizedString(forStatusCode: httpResp.statusCode)
                return ZitiError("HTTP response code: \(httpResp.statusCode) \(respStr)")
            }
            return ZitiError(edgeErrorResp.shortDescription(httpResp.statusCode))
        }
        return nil
    }
    
    private func getKeys(_ zkc:ZitiKeychain) -> (SecKey?, SecKey?, ZitiError?) {
        var privKey:SecKey?, pubKey:SecKey?, error:ZitiError?
        
        // Should we delete keys and create new one if they already exist?  Or just always create
        // new keys and leave it to caller to clean up after themselves?  We only have the id to search
        // on, so if we have multiple with the same id things will get goofy...
        if zkc.keyPairExists() == false {
            (privKey, pubKey, error) = zkc.createKeyPair()
            guard error == nil else {
                return (nil, nil, error)
            }
        } else {
            (privKey, pubKey, error) = zkc.getKeyPair()
            guard error == nil else {
                return (nil, nil, error)
            }
        }
        return (privKey, pubKey, nil)
    }
}

extension ZitiEdge : URLSessionDelegate {
    func handleClientCertChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        let zkc = ZitiKeychain(self.zid)
        let (identity, err) = zkc.getSecureIdentity()
        guard err == nil else {
            print("...no SecIdentity for \(zid.name) - will perform default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let urlCredential = URLCredential(identity: identity!, certificates: nil, persistence: .forSession)
        completionHandler(.useCredential, urlCredential)
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        print("RECEIVED CHALLENGE: \(challenge.protectionSpace.authenticationMethod)")
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrustChallenge(challenge, completionHandler:completionHandler)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertChallenge(challenge, completionHandler:completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
