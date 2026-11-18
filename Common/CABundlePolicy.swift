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
import CryptoKit

/// The networks identities may belong to, by the CA certificates they trust (`allowedCAs`).
/// The C SDK trusts exactly an identity's CA bundle for its controllers and routers, and accepts partial chains, so every
/// certificate in the bundle is a trust anchor. An identity is allowed only if each one is allowed or chains, within the
/// bundle, to one that is. An empty bundle isn't allowed: the SDK would fall back to the system's CAs.
struct CABundlePolicy : Equatable {
    enum Result : Equatable {
        case allowed
        case blocked(String)
    }

    static let notAllowedMessage = "This network isn't allowed by your organization."
    static let blockedStatus = "Blocked by your organization"

    /// SHA-256 fingerprints of the allowed certificates (DER), lowercase hex without separators
    let fingerprints:Set<String>

    /// Fingerprints in hex, any case, colons optional. Invalid ones are logged and skipped; a policy with none allows nothing
    init(_ values:[String]) {
        var fingerprints = Set<String>()
        for (i, value) in values.enumerated() {
            guard let fingerprint = CABundlePolicy.normalize(value) else {
                zLog.warn("Ignoring invalid CA fingerprint \(i + 1)")
                continue
            }
            fingerprints.insert(fingerprint)
        }
        self.fingerprints = fingerprints
    }

    func check(_ caBundle:String?) -> Result {
        guard let certs = CABundlePolicy.certificates(caBundle) else { return .blocked("CA bundle can't be read") }
        guard !certs.isEmpty else { return .blocked("no CA bundle") }

        let anchors = certs.filter { fingerprints.contains(CABundlePolicy.fingerprint($0)) }
        for cert in certs where !fingerprints.contains(CABundlePolicy.fingerprint(cert)) {
            guard CABundlePolicy.chains(cert, certs, anchors) else {
                return .blocked("CA \(CABundlePolicy.displayFingerprint(cert)) isn't allowed")
            }
        }
        return .allowed
    }

    /// An enrolled identity the tunnel won't load. Pending ones are checked when they enroll
    func blocks(_ zid:ZitiIdentity) -> Bool {
        return zid.isEnrolled && check(zid.czid?.ca) != .allowed
    }

    /// SHA-256 over DER, lowercase hex
    static func fingerprint(_ cert:SecCertificate) -> String {
        return SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
    }

    /// As `openssl x509 -fingerprint -sha256` shows it, so admins can compare
    static func displayFingerprint(_ cert:SecCertificate) -> String {
        return SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// The certificates in a PEM bundle (optionally "pem:" prefixed, as the SDK stores it), or nil if it can't be read.
    /// Only CERTIFICATE blocks and whitespace are accepted: the SDK reads more ("file:" references, paths, legacy
    /// "X509 CERTIFICATE" blocks), so anything else could hide certificates from the check
    static func certificates(_ caBundle:String?) -> [SecCertificate]? {
        let begin = "-----BEGIN CERTIFICATE-----", end = "-----END CERTIFICATE-----"
        var certs:[SecCertificate] = []
        var rest = Substring(caBundle ?? "")
        if rest.hasPrefix("pem:") { rest = rest.dropFirst(4) }
        while true {
            rest = rest.drop { $0.isWhitespace }
            guard !rest.isEmpty else { return certs }
            guard rest.hasPrefix(begin), let e = rest.range(of: end),
                  let der = Data(base64Encoded: String(rest[rest.index(rest.startIndex, offsetBy: begin.count)..<e.lowerBound].filter { !$0.isWhitespace })),
                  let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
            certs.append(cert)
            rest = rest[e.upperBound...]
        }
    }

    /// The certificates as a plain PEM bundle. The tunnel gives the SDK this rather than the identity's own text, so the
    /// SDK loads exactly what was checked
    static func pem(_ certs:[SecCertificate]) -> String {
        return certs.map { cert in
            let b64 = (SecCertificateCopyData(cert) as Data).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            return "-----BEGIN CERTIFICATE-----\n\(b64)\n-----END CERTIFICATE-----\n"
        }.joined()
    }

    private static func normalize(_ value:String) -> String? {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ":", with: "").lowercased()
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hex
    }

    /// Whether `cert` chains, within the bundle, to one of `anchors`. Judged at times inside the certificate's own validity,
    /// since the question is which network it belongs to, not whether it's current: signatures decide, dates don't
    private static func chains(_ cert:SecCertificate, _ bundle:[SecCertificate], _ anchors:[SecCertificate]) -> Bool {
        var trust:SecTrust?
        guard !anchors.isEmpty,
              SecTrustCreateWithCertificates([cert] + bundle as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust = trust,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }

        var dates = [Date()]
        if let (notBefore, notAfter) = validity(cert) {
            dates = [notBefore, notBefore.addingTimeInterval(notAfter.timeIntervalSince(notBefore) / 2), notAfter]
        }
        return dates.contains { date in
            SecTrustSetVerifyDate(trust, date as CFDate) == errSecSuccess && SecTrustEvaluateWithError(trust, nil)
        }
    }

    /// notBefore and notAfter, read from the DER (Certificate > TBSCertificate > Validity). Security's accessors need
    /// macOS 15 / iOS 18
    static func validity(_ cert:SecCertificate) -> (Date, Date)? {
        var der = DER(SecCertificateCopyData(cert) as Data)
        guard var certificate = der.next(0x30), var tbs = certificate.next(0x30) else { return nil }
        if tbs.peek == 0xA0 { _ = tbs.next() } // version
        guard tbs.next() != nil, tbs.next() != nil, tbs.next() != nil, // serial, signature algorithm, issuer
              var validity = tbs.next(0x30), let notBefore = validity.time(), let notAfter = validity.time() else { return nil }
        return (notBefore, notAfter)
    }
}

/// Just enough DER to reach a certificate's validity
private struct DER {
    private let bytes:[UInt8]
    private var i:Int

    init(_ data:Data) {
        self.init(Array(data))
    }

    private init(_ bytes:[UInt8]) {
        self.bytes = bytes
        i = 0
    }

    var peek:UInt8? {
        return i < bytes.count ? bytes[i] : nil
    }

    /// The next element's contents, if it has the expected tag (any tag when nil)
    mutating func next(_ tag:UInt8? = nil) -> DER? {
        guard i + 2 <= bytes.count, tag == nil || bytes[i] == tag else { return nil }
        var length = Int(bytes[i + 1])
        var start = i + 2
        if length & 0x80 != 0 {
            let n = length & 0x7f
            guard n > 0, n <= 4, start + n <= bytes.count else { return nil }
            length = bytes[start..<start + n].reduce(0) { $0 << 8 | Int($1) }
            start += n
        }
        guard start + length <= bytes.count else { return nil }
        i = start + length
        return DER(Array(bytes[start..<start + length]))
    }

    /// UTCTime (YYMMDDHHMMSSZ, 1950-2049) or GeneralizedTime (YYYYMMDDHHMMSSZ)
    mutating func time() -> Date? {
        guard let tag = peek, tag == 0x17 || tag == 0x18, let value = next(),
              let text = String(bytes: value.bytes, encoding: .ascii), text.hasSuffix("Z") else { return nil }
        let digits = text.dropLast()
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.count == (tag == 0x17 ? 12 : 14) else { return nil }
        var fields = Array(digits).map { Int(String($0))! }
        var year:Int
        if tag == 0x17 {
            year = fields[0] * 10 + fields[1]
            year += year < 50 ? 2000 : 1900
            fields.removeFirst(2)
        } else {
            year = fields[0...3].reduce(0) { $0 * 10 + $1 }
            fields.removeFirst(4)
        }
        let pair = { (i:Int) in fields[i] * 10 + fields[i + 1] }
        var comps = DateComponents(year: year, month: pair(0), day: pair(2), hour: pair(4), minute: pair(6), second: pair(8))
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)
    }
}
