//
// Copyright NetFoundry Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
@testable import Ziti_Desktop_Edge

// MARK: - JSON Decoding

func decodeJSON<T: Decodable>(_ type: T.Type, from dict: [String: Any]) -> T {
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(type, from: data)
}

// MARK: - ZitiIdentity Factory

func makeIdentity(
    id: String = "test-id",
    ztAPI: String = "https://ctrl.example.com",
    name: String = "test-identity",
    enrolled: Bool = false,
    enabled: Bool = false,
    enrollTo: String? = nil,
    mfaEnabled: Bool? = nil,
    mfaVerified: Bool? = nil,
    mfaPending: Bool? = nil,
    extAuthPending: Bool? = nil,
    expiration: Int? = nil,
    claims: [String: Any]? = nil,
    jwtProviders: [[String: Any]]? = nil,
    services: [[String: Any]] = []
) -> ZitiIdentity {
    var json: [String: Any] = [
        "enrolled": enrolled,
        "enabled": enabled,
        "services": services,
        "czid": [
            "id": id,
            "ztAPI": ztAPI,
            "ztAPIs": [ztAPI],
            "name": name
        ]
    ]
    if let enrollTo = enrollTo { json["enrollTo"] = enrollTo }
    if let mfaEnabled = mfaEnabled { json["mfaEnabled"] = mfaEnabled }
    if let mfaVerified = mfaVerified { json["mfaVerified"] = mfaVerified }
    if let mfaPending = mfaPending { json["mfaPending"] = mfaPending }
    if let extAuthPending = extAuthPending { json["extAuthPending"] = extAuthPending }
    if let jwtProviders = jwtProviders { json["jwtProviders"] = jwtProviders }
    if let claims = claims {
        json["claims"] = claims
    } else if let exp = expiration {
        json["claims"] = ["sub": id, "iss": ztAPI, "exp": exp]
    }
    return decodeJSON(ZitiIdentity.self, from: json)
}

// MARK: - ZitiService Factory

func makeService(
    name: String = "test-svc",
    id: String = "svc-1",
    needsRestart: Bool = false,
    postureQuerySets: [[String: Any]]? = nil
) -> ZitiService {
    var json: [String: Any] = ["name": name, "id": id]
    json["status"] = [
        "lastUpdatedAt": Date().timeIntervalSince1970,
        "status": "Available",
        "needsRestart": needsRestart
    ] as [String : Any]
    if let pqs = postureQuerySets { json["postureQuerySets"] = pqs }
    return decodeJSON(ZitiService.self, from: json)
}

// MARK: - Posture Query Helpers

func makePQS(isPassing: Bool, queries: [[String: Any]]? = nil) -> [String: Any] {
    var dict: [String: Any] = ["isPassing": isPassing, "policyId": UUID().uuidString]
    if let queries = queries { dict["postureQueries"] = queries }
    return dict
}

func makePQ(isPassing: Bool, queryType: String) -> [String: Any] {
    return ["isPassing": isPassing, "queryType": queryType, "id": UUID().uuidString]
}

// MARK: - Service JSON with Posture Queries

func makeServiceJSON(
    name: String = "test-svc",
    id: String = "svc-1",
    needsRestart: Bool = false,
    postureQuerySets: [[String: Any]]? = nil
) -> [String: Any] {
    var json: [String: Any] = ["name": name, "id": id]
    json["status"] = [
        "lastUpdatedAt": Date().timeIntervalSince1970,
        "status": "Available",
        "needsRestart": needsRestart
    ] as [String : Any]
    if let pqs = postureQuerySets { json["postureQuerySets"] = pqs }
    return json
}
