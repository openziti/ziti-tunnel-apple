//
//  DNSFilter.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/28/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import Foundation

class DNSFilter : NSObject {
    
    static func shouldFilter(_ q:DNSQuestion) -> Bool {
        return DNSFilter.dnsLocallServed.contains{ suffix in
            return q.name.nameString.uppercased().hasSuffix(suffix)
        }
    }
    
    // https://www.iana.org/assignments/locally-served-dns-zones/locally-served-dns-zones.xhtml
    static let dnsLocallServed:[String] = [
        "10.IN-ADDR.ARPA",
        "16.172.IN-ADDR.ARPA",
        "17.172.IN-ADDR.ARPA",
        "18.172.IN-ADDR.ARPA",
        "19.172.IN-ADDR.ARPA",
        "20.172.IN-ADDR.ARPA",
        "21.172.IN-ADDR.ARPA",
        "22.172.IN-ADDR.ARPA",
        "23.172.IN-ADDR.ARPA",
        "24.172.IN-ADDR.ARPA",
        "25.172.IN-ADDR.ARPA",
        "26.172.IN-ADDR.ARPA",
        "27.172.IN-ADDR.ARPA",
        "28.172.IN-ADDR.ARPA",
        "29.172.IN-ADDR.ARPA",
        "30.172.IN-ADDR.ARPA",
        "31.172.IN-ADDR.ARPA",
        "168.192.IN-ADDR.ARPA",
        "0.IN-ADDR.ARPA",
        "127.IN-ADDR.ARPA",
        "254.169.IN-ADDR.ARPA",
        "2.0.192.IN-ADDR.ARPA",
        "100.51.198.IN-ADDR.ARPA",
        "113.0.203.IN-ADDR.ARPA",
        "255.255.255.255.IN-ADDR.ARPA",
        "64.100.IN-ADDR.ARPA",
        "65.100.IN-ADDR.ARPA",
        "66.100.IN-ADDR.ARPA",
        "67.100.IN-ADDR.ARPA",
        "68.100.IN-ADDR.ARPA",
        "69.100.IN-ADDR.ARPA",
        "70.100.IN-ADDR.ARPA",
        "71.100.IN-ADDR.ARPA",
        "72.100.IN-ADDR.ARPA",
        "73.100.IN-ADDR.ARPA",
        "74.100.IN-ADDR.ARPA",
        "75.100.IN-ADDR.ARPA",
        "76.100.IN-ADDR.ARPA",
        "77.100.IN-ADDR.ARPA",
        "78.100.IN-ADDR.ARPA",
        "79.100.IN-ADDR.ARPA",
        "80.100.IN-ADDR.ARPA",
        "81.100.IN-ADDR.ARPA",
        "82.100.IN-ADDR.ARPA",
        "83.100.IN-ADDR.ARPA",
        "84.100.IN-ADDR.ARPA",
        "85.100.IN-ADDR.ARPA",
        "86.100.IN-ADDR.ARPA",
        "87.100.IN-ADDR.ARPA",
        "88.100.IN-ADDR.ARPA",
        "89.100.IN-ADDR.ARPA",
        "90.100.IN-ADDR.ARPA",
        "91.100.IN-ADDR.ARPA",
        "92.100.IN-ADDR.ARPA",
        "93.100.IN-ADDR.ARPA",
        "94.100.IN-ADDR.ARPA",
        "95.100.IN-ADDR.ARPA",
        "96.100.IN-ADDR.ARPA",
        "97.100.IN-ADDR.ARPA",
        "98.100.IN-ADDR.ARPA",
        "99.100.IN-ADDR.ARPA",
        "100.100.IN-ADDR.ARPA",
        "101.100.IN-ADDR.ARPA",
        "102.100.IN-ADDR.ARPA",
        "103.100.IN-ADDR.ARPA",
        "104.100.IN-ADDR.ARPA",
        "105.100.IN-ADDR.ARPA",
        "106.100.IN-ADDR.ARPA",
        "107.100.IN-ADDR.ARPA",
        "108.100.IN-ADDR.ARPA",
        "109.100.IN-ADDR.ARPA",
        "110.100.IN-ADDR.ARPA",
        "111.100.IN-ADDR.ARPA",
        "112.100.IN-ADDR.ARPA",
        "113.100.IN-ADDR.ARPA",
        "114.100.IN-ADDR.ARPA",
        "115.100.IN-ADDR.ARPA",
        "116.100.IN-ADDR.ARPA",
        "117.100.IN-ADDR.ARPA",
        "118.100.IN-ADDR.ARPA",
        "119.100.IN-ADDR.ARPA",
        "120.100.IN-ADDR.ARPA",
        "121.100.IN-ADDR.ARPA",
        "122.100.IN-ADDR.ARPA",
        "123.100.IN-ADDR.ARPA",
        "124.100.IN-ADDR.ARPA",
        "125.100.IN-ADDR.ARPA",
        "126.100.IN-ADDR.ARPA",
        "127.100.IN-ADDR.ARPA"
    ]
}
