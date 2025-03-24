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
import UserNotifications

class UserNotifications {
    enum Action : String {
        case Open = "Open", MfaAuth = "MfaAuth", Restart = "Restart", ExtAuth = "ExtAuth"
        
        var title:String {
            switch self {
            case .Open:    return "Open"
            case .MfaAuth: return "Auth Now"
            case .Restart: return "Restart"
            case .ExtAuth: return "External Authentication Required"
            }
        }
        
        static func actionForTitle(_ title:String) -> Action? {
            switch title {
            case Action.Open.title: return Action.Open
            case Action.MfaAuth.title: return Action.MfaAuth
            case Action.Restart.title: return Action.Restart
            case Action.ExtAuth.title: return Action.ExtAuth
            default: return nil
            }
        }
        
        var action:UNNotificationAction {
            switch self {
            case .Open:    return UNNotificationAction(identifier: Action.Open.rawValue, title: Action.Open.title, options: [.foreground])
            case .MfaAuth: return UNNotificationAction(identifier: Action.MfaAuth.rawValue, title: Action.MfaAuth.title, options: [.foreground])
            case .Restart: return UNNotificationAction(identifier: Action.Restart.rawValue, title: Action.Restart.title, options: [.foreground])
            case .ExtAuth: return UNNotificationAction(identifier: Action.ExtAuth.rawValue, title: Action.ExtAuth.title, options: [.foreground])
            }
        }
    }
    
    enum Category : String {
        case Info = "INFO", Error = "ERROR", Posture = "POSTURE", Restart = "RESTART", Mfa = "MFA", Ext = "EXT"
        
        var actions:[UNNotificationAction] {
            switch self {
            case .Info:    return []
            case .Error:   return []
            case .Posture: return []
            case .Restart: return [ Action.Restart.action ]
            case .Mfa:     return [ Action.MfaAuth.action ]
            case .Ext:     return [ Action.ExtAuth.action ]
            }
        }
        
        var category:UNNotificationCategory {
            switch self {
            case .Info:    return UNNotificationCategory.init(identifier: Category.Info.rawValue,
                                                              actions: Category.Info.actions,
                                                              intentIdentifiers: [], options: [])
            case .Error:   return UNNotificationCategory.init(identifier: Category.Error.rawValue,
                                                              actions: Category.Error.actions,
                                                              intentIdentifiers: [], options: [])
            case .Posture: return UNNotificationCategory.init(identifier: Category.Posture.rawValue,
                                                              actions: Category.Posture.actions,
                                                              intentIdentifiers: [], options: [])
            case .Restart: return UNNotificationCategory.init(identifier: Category.Restart.rawValue,
                                                              actions: Category.Restart.actions,
                                                              intentIdentifiers: [], options: [])
            case .Mfa:     return UNNotificationCategory.init(identifier: Category.Mfa.rawValue,
                                                              actions: Category.Mfa.actions,
                                                              intentIdentifiers: [], options: [])
            case .Ext:     return UNNotificationCategory.init(identifier: Category.Ext.rawValue,
                                                              actions: Category.Ext.actions,
                                                              intentIdentifiers: [], options: [])
            }
        }
        
        static var allCategories:Set<UNNotificationCategory> {
            return [ Category.Info.category, Category.Error.category, Category.Posture.category, Category.Restart.category, Category.Mfa.category, Category.Ext.category]
        }
    }
    
    static let shared = UserNotifications()
    private init() {}
        
    func requestAuth() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { authorized, error in
            zLog.info("Auth request authorized? \(authorized)")
            center.setNotificationCategories(Category.allCategories)
        }
    }
    
    func post(_ category:Category, _ subtitle:String?, _ body:String?=nil, _ zid:ZitiIdentity?=nil, _ completionHandler: (()->Void)?=nil) {
        zLog.info("Attempting to post \(category) notification, subitile:\(subtitle as Any), body:\(body as Any), zid:\(zid?.name as Any)")
        
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            zLog.debug("Notification settings: \(settings.debugDescription)")
            
            guard settings.authorizationStatus == .authorized else {
                zLog.warn("Not authorized to send notifications")
                completionHandler?()
                return
            }
            
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = category.rawValue
            content.title = ProviderConfig().localizedDescription
            
            if let subtitle = subtitle { content.subtitle = subtitle }
            if let body = body { content.body = body }
            
            var requestId = "ZitiNotification-\(category.rawValue)"
            if let zid = zid {
                content.userInfo["zid"] = zid.id
                requestId += "-\(zid.id)"
            }
            
            let request = UNNotificationRequest(identifier: requestId, content: content, trigger: nil)
            center.add(request) { error in
                if let error = error {
                    zLog.error("Unble to schedule request: \(error.localizedDescription)")
                }
                completionHandler?()
            }
        }
    }
}
