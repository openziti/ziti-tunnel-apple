//
//  Version.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 4/30/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class Version {
    static var appVersion:String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown version"
    }
    
    static var appBuild:String? {
        if let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return "(\(appBuild))"
        }
        return nil
    }
    
    static var osVersion:String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    static var str:String {
        var appVersion = Version.appVersion
        if let appBuild  = Version.appBuild {
            appVersion += " \(appBuild)"
        }
        return appVersion
    }
    
    static var verboseStr:String {
        return "\(Bundle.main.bundleIdentifier ?? "Ziti") Version: \(Version.str), OS: \(osVersion)"
    }
}
