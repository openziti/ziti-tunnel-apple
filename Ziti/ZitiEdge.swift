//
//  ZitiEdge.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/5/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

fileprivate let AUTH_PATH = "/authenticate?method=cert"
fileprivate let SESSION_TAG = "zt-session"
fileprivate let SERVCES_PATH = "/services?limit=5000"
fileprivate let NETSESSIONS_PATH = "/network-sessions?limit=1000"
fileprivate let GET_METHOD = "GET"
fileprivate let POST_METHOD = "POST"
fileprivate let CONTENT_TYPE = "Content-Type"
fileprivate let JSON_TYPE = "application/json; charset=utf-8"
fileprivate let TEXT_TYPE = "text/plain; charset=utf-8"
fileprivate let PEM_CERTIFICATE = "CERTIFICATE"
fileprivate let PEM_CERTIFICATE_REQUEST = "CERTIFICATE REQUEST"

class ZitiEdge : NSObject {    
    weak var zid:ZitiIdentity!
    init(_ zid:ZitiIdentity) {
        self.zid = zid
    }
    
    func authenticate(completionHandler: @escaping (ZitiError?) -> Void) {
        guard let url = URL(string: AUTH_PATH, relativeTo:URL(string:zid.apiBaseUrl)) else {
            completionHandler(ZitiError("Enable to convert auth URL \"\(AUTH_PATH)\" for \"\(zid.apiBaseUrl)\""))
            return
        }
        
        let urlRequest = createRequest(url, method:POST_METHOD, contentType:JSON_TYPE, body:nil)
        urlSession.dataTask(with: urlRequest) { (data, response, error) in
            if let zErr = self.validateResponse(data, response, error) {
                completionHandler(zErr)
                return
            }
            
            guard
                let json = ((try? JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any]) as [String : Any]??),
                let dataJSON = json?["data"] as? [String: Any],
                let sessionJSON = dataJSON["session"] as? [String:Any],
                let token = sessionJSON["token"] as? String
            else {
                completionHandler(ZitiError("error trying to convert data to JSON"))
                return
            }
            print("zt-session: \(token)")
            self.zid.sessionToken = token
            completionHandler(nil)
        }.resume()
    }
    
    func getHost(_ urlString:String) -> String {
        guard let url = URL(string: urlString) else { return "" }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.host ?? ""
    }
    
    func enroll(completionHandler: @escaping (ZitiError?) -> Void) {
        guard let url = URL(string: zid.enrollmentUrl) else {
            completionHandler(ZitiError("Enable to convert enrollment URL \"\(zid.enrollmentUrl)\""))
            return
        }
        
        // Get Keys
        let (privKey, pubKey, keyErr) = getKeys(zid)
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
        let zkc = ZitiKeychain()
        let csrPEM = zkc.convertToPEM(PEM_CERTIFICATE_REQUEST, der: csr!).data(using: String.Encoding.utf8)
        let urlRequest = createRequest(url, method:POST_METHOD, contentType:TEXT_TYPE, body:csrPEM)
        
        // don't share session with other edge calls since we have no secId at this point
        let enrollSession = URLSession(configuration: URLSessionConfiguration.default, delegate:self, delegateQueue:OperationQueue.main)
        enrollSession.dataTask(with: urlRequest) { (data, response, error) in
            if let zErr = self.validateResponse(data, response, error) {
                completionHandler(zErr)
                return
            }
            guard let certPEM = String(data: data!, encoding: .utf8) else {
                completionHandler(ZitiError("Unable to encode PEM data"))
                return
            }
            let certDER = zkc.convertToDER(certPEM)
            
            let (_, zStoreErr) = zkc.storeCertificate(certDER, label:self.zid.id)
            if zStoreErr != nil {
                completionHandler(zStoreErr)
                return
            }

            self.zid.enrolled = true
            completionHandler(nil)
        }.resume()
        enrollSession.finishTasksAndInvalidate()
    }
    
    func getServices(completionHandler: @escaping (Bool, ZitiError?) -> Void) {
        guard let url = URL(string: SERVCES_PATH, relativeTo:URL(string:zid.apiBaseUrl)) else {
            completionHandler(false, ZitiError("Enable to convert URL \"\(SERVCES_PATH)\" for \"\(zid.apiBaseUrl)\""))
            return
        }
        let urlRequest = createRequest(url, method:GET_METHOD, contentType:JSON_TYPE, body:nil)
        urlSession.dataTask(with: urlRequest) { (data, response, error) in
            if let zErr = self.validateResponse(data, response, error) {
                if zErr.errorCode == ZitiError.AuthRequired {
                    self.authenticate { authErr in
                        guard authErr == nil else {
                            let numServices = self.zid.services?.count ?? 0
                            self.zid.services = nil
                            let didChange = numServices > 0
                            completionHandler(didChange, authErr)
                            return
                        }
                        self.getServices(completionHandler: completionHandler)
                    }
                } else {
                    completionHandler(false, zErr)
                }
                return
            }
            guard let resp =
                try? JSONDecoder().decode(ZitiEdgeServiceResponse.self, from: data!) else {
                completionHandler(false, ZitiError("Enable to decode response for services"))
                return
            }
            
            // update the returned services with any cached netSession data
            var misMatch = false
            self.zid.services?.forEach { svc in
                if let match = resp.data?.first(where: { $0.id == svc.id}) {
                    match.networkSession = svc.networkSession
                    match.status = svc.status
                    match.dns?.interceptIp = svc.dns?.interceptIp
                } else {
                    misMatch = true
                }
            }
            var didChange = misMatch
            if misMatch == false {
                // deeper comparison...
                didChange = self.zid.doServicesMatch(resp.data) == false
            }
            self.zid.services = resp.data
            print("got \(self.zid.services?.count ?? 0) services for \(self.zid.name). didChange=\(didChange)")
            completionHandler(didChange, nil)
        }.resume()
    }
    
    func getNetworkSession(_ serviceId:String, completionHandler: @escaping (ZitiError?) -> Void) {
        guard let url = URL(string: NETSESSIONS_PATH, relativeTo:URL(string:zid.apiBaseUrl)) else {
            completionHandler(ZitiError("Enable to convert URL \"\(NETSESSIONS_PATH)\" for \"\(zid.apiBaseUrl)\""))
            return
        }
        guard let services = zid.services else {
            completionHandler(
                ZitiError("Unable to getNetworkSession for service \(serviceId). No services available to \(zid.name)"))
            return
        }
        guard let service = services.first(where: { $0.id == serviceId }) else {
            completionHandler(
                    ZitiError("Unable to getNetworkSession for service \(serviceId). Service not found for \(zid.name)"))
            return
        }
        
        let body = "{\"serviceId\":\"\(serviceId)\"}".data(using: .utf8)
        let urlRequest = createRequest(url, method:POST_METHOD, contentType:JSON_TYPE, body:body)
        urlSession.dataTask(with: urlRequest) { (data, response, error) in
            if let zErr = self.validateResponse(data, response, error) {
                // if 401, try auth and if ok, try getNetworkSession() again.
                if zErr.errorCode == ZitiError.AuthRequired {
                    self.authenticate { authErr in
                        guard authErr == nil else {
                            completionHandler(authErr)
                            return
                        }
                        self.getNetworkSession(serviceId, completionHandler: completionHandler)
                    }
                } else {
                    completionHandler(zErr)
                }
                return
            }
            guard let resp =
                try? JSONDecoder().decode(ZitiEdgeNetworkSessionResponse.self, from: data!) else {
                    completionHandler(ZitiError("Enable to decode response for network session"))
                    return
            }
            service.networkSession = resp.data
            completionHandler(nil)
        }.resume()
    }
    
    private func createRequest(_ url:URL, method:String, contentType:String, body:Data?) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue(contentType, forHTTPHeaderField: CONTENT_TYPE)
        urlRequest.setValue(zid.sessionToken ?? "-1", forHTTPHeaderField: SESSION_TAG)
        urlRequest.httpBody = body
        return urlRequest
    }
    
    private func validateResponse(_ data:Data?, _ response:URLResponse?, _ error:Error?) -> ZitiError? {
        guard error == nil,
            let httpResp = response as? HTTPURLResponse,
            let respData = data
        else {
            self.zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status:.Unavailable)
            var errorCode = -1
            if let nsErr = error as NSError?, nsErr.domain == NSURLErrorDomain {
                errorCode = ZitiError.URLError
            }
            return ZitiError(error?.localizedDescription ??
                "Invalid or empty response from server", errorCode:errorCode)
        }
        
        guard httpResp.statusCode >= 200 && httpResp.statusCode < 300 else {
            self.zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status:.PartiallyAvailable)
            guard let edgeErrorResp = try? JSONDecoder().decode(ZitiEdgeErrorResponse.self, from: respData) else {
                let respStr = HTTPURLResponse.localizedString(forStatusCode: httpResp.statusCode)
                return ZitiError("HTTP response code: \(httpResp.statusCode) \(respStr)", errorCode:httpResp.statusCode)
            }            
            return ZitiError(edgeErrorResp.shortDescription(httpResp.statusCode), errorCode:httpResp.statusCode)
        }
        self.zid.edgeStatus = ZitiIdentity.EdgeStatus(Date().timeIntervalSince1970, status:.Available)
        
        // TODO: temp for dev
        //if let responseStr = String(data: respData, encoding: String.Encoding.utf8) {
            //print("Response for \(zid?.name ?? ""): \(responseStr)")
        //}
        // end temp for dev
        return nil
    }
    
    private func getKeys(_ zid:ZitiIdentity) -> (SecKey?, SecKey?, ZitiError?) {
        var privKey:SecKey?, pubKey:SecKey?, error:ZitiError?
        
        // Should we delete keys and create new one if they already exist?  Or just always create
        // new keys and leave it to caller to clean up after themselves?  We only have the id to search
        // on, so if we have multiple with the same id things will get goofy...
        let zkc = ZitiKeychain()
        if zkc.keyPairExists(zid) == false {
            (privKey, pubKey, error) = zkc.createKeyPair(zid)
            guard error == nil else {
                return (nil, nil, error)
            }
        } else {
            (privKey, pubKey, error) = zkc.getKeyPair(zid)
            guard error == nil else {
                return (nil, nil, error)
            }
        }
        return (privKey, pubKey, nil)
    }
    
    private var hasSession = false
    private lazy var urlSession:URLSession = {
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate:self, delegateQueue:OperationQueue.main)
        hasSession = true
        return session
    }()
    
    func finishTasksAndInvalidate() {
        if hasSession == true {
            urlSession.finishTasksAndInvalidate()
        }
    }
}

extension ZitiEdge : URLSessionDelegate {
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrustChallenge(challenge, completionHandler:completionHandler)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertChallenge(challenge, completionHandler:completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    private func isExpectedHost(_ host:String) -> Bool {
        let apiHost = getHost(zid.apiBaseUrl)
        let enrollHost = getHost(zid.enrollmentUrl)
        return host == apiHost || host == enrollHost
    }
    
    func handleServerTrustChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard let rootCa = zid.rootCa else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            NSLog("ServerTrustChallenge: ServerTrust not available. Performming default handling.")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if isExpectedHost(challenge.protectionSpace.host) == false {
            NSLog("Rejecting server challend for unexpected host \(challenge.protectionSpace.host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        
        //
        // TODO: need to re-visit this...
        // https://tools.ietf.org/html/rfc5246#section-7.4.2
        // certificate_list This is a sequence (chain) of certificates. The sender's certificate MUST come first in the list. Each following certificate MUST directly certify the one preceding it. Because certificate validation requires that root keys be distributed independently, the self-signed certificate that specifies the root certificate authority MAY be omitted from the chain, under the assumption that the remote end must already possess it in order to validate it in any case.
        //
        // Rely on SecTrustEvaluateAsync to verify certs were signed with correct private key
        let steStatus = SecTrustEvaluateAsync(serverTrust, DispatchQueue.main) { secTrust, result in
            if result == .proceed || result == .unspecified {
                completionHandler(.useCredential, URLCredential(trust:secTrust))
            } else if result == .recoverableTrustFailure {
                var recovered = false
                let zkc = ZitiKeychain()
                
                // TODO: this is the part that needs work...
                //    improvment on below: validate the chain is as described above,
                //    that index 0 chains all the way to the last one
                //    if last is a root CA, verify that we have it.
                //    if last is not a root CA, verify that we have it and that the signer was root CA in our rootCa
                for i in 0..<SecTrustGetCertificateCount(secTrust) {
                    if let cert = SecTrustGetCertificateAtIndex(secTrust, i) {
                        for caCert in zkc.PEMstoCerts(zkc.extractPEMs(rootCa)) {
                            if zkc.certsMatch(cert, caCert) {
                                recovered = true
                                completionHandler(.useCredential, URLCredential(trust: secTrust))
                                break
                            }
                        }
                    }
                    if recovered { break }
                }
                if !recovered {
                    // Will (very) likely fail, but give default handling a chance..
                    NSLog("Unable to validate server trust. Performing default handling.")
                    completionHandler(.performDefaultHandling, nil)
                }
            } else {
                // reject
                NSLog("Non-recoverable error evaluating server trust. Rejecting.")
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
        
        if steStatus != errSecSuccess {
            NSLog("Unable to evaluate server trust. Rejecting")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    func handleClientCertChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        guard let identity = zid.secId else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let urlCredential = URLCredential(identity: identity, certificates: nil, persistence:.forSession)
        completionHandler(.useCredential, urlCredential)
    }
}
