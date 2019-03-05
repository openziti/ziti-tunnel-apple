//
//  ZitiEdge.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/5/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiEdge : NSObject {
    
    func enroll(_ zid:ZitiIdentity, completionHandler: @escaping (ZitiError?) -> Void) {
        // Got a URL?
        guard let url = URL(string: zid.enrollmentUrl) else {
            completionHandler(ZitiError("Enable to convert enrillment URL \"\(zid.enrollmentUrl)\""))
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
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = zkc.convertToPEM("CERTIFICATE REQUEST", der: csr!).data(using: String.Encoding.utf8)
        
        URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            guard error == nil,
                let httpResp = response as? HTTPURLResponse,
                let respData = data
                else {
                    if error != nil { print(error!) }
                    completionHandler(ZitiError(error?.localizedDescription ??
                        "Invalid or empty response from enrollment server"))
                    return
            }
            
            guard httpResp.statusCode == 200 else {
                guard let json = try? JSONSerialization.jsonObject(with:respData, options:[]) as? [String:Any],
                    let errorJSON = json?["error"] as? [String:Any],
                    let causeMessage = errorJSON["causeMessage"] as? String
                    else {
                        let respStr = HTTPURLResponse.localizedString(forStatusCode: httpResp.statusCode)
                        completionHandler(ZitiError("HTTP response code: \(httpResp.statusCode) \(respStr)"))
                        return
                }
                completionHandler(ZitiError(causeMessage))
                return
            }
            
            // Grab the returned cert.  wonder how it shows?  Grab it and find out...
            // Store the Certificate (zkc.convertToDER, zkc.storeCertificate, set Enrolled = true and Enabled = true,
            //    and update the identity file?
            let certPEM = String(data: respData, encoding: .utf8)
            print(certPEM ?? "Unable to get PEM from response data")
            let certDER = zkc.convertToDER(certPEM!) // todo: guard certPEM...
            _ = zkc.storeCertificate(certDER) // todo: error check
            
            zid.enrolled = true
            completionHandler(nil)
            }.resume()
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
