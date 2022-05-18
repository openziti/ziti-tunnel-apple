//
// Copyright NetFoundry, Inc.
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
    enum Category : String {
        case Info = "INFO", Error = "ERROR", Posture = "POSTURE", Restart = "RESTART", Mfa = "MFA"
    }
    
    enum Action : String {
        case Open = "Open", MfaAuth = "MfaAuth", Restart = "Restart"
    }
    
    static let shared = UserNotifications()
    private init() {}
    
    func requestAuth() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { authorized, error in
            zLog.info("Auth request authorized? \(authorized)")
            
            let openAction = UNNotificationAction(identifier: Action.Open.rawValue, title: "Open", options: [.foreground])
            let mfaAction = UNNotificationAction(identifier: Action.MfaAuth.rawValue, title: "Auth Now", options: [.foreground])
            let restartAction = UNNotificationAction(identifier: Action.Restart.rawValue, title: "Restart", options: [.foreground])
            
            let infoCategory = UNNotificationCategory.init(identifier: Category.Info.rawValue, actions: [], intentIdentifiers: [], options: [])
            let errorCategory = UNNotificationCategory.init(identifier: Category.Error.rawValue, actions: [], intentIdentifiers: [], options: [])
            let postureCategory = UNNotificationCategory.init(identifier: Category.Posture.rawValue, actions: [], intentIdentifiers: [], options: [])
            
            let restartActions = [ restartAction, openAction ]
            let restartCategory = UNNotificationCategory.init(identifier: Category.Restart.rawValue, actions: restartActions, intentIdentifiers: [], options: [])
            
            let mfaActions = [mfaAction, openAction]
            let mfaCatgory = UNNotificationCategory.init(identifier: Category.Mfa.rawValue, actions: mfaActions, intentIdentifiers: [], options: [])
            
            let categories:Set = [infoCategory, errorCategory, postureCategory, restartCategory, mfaCatgory]
            center.setNotificationCategories(categories)
        }
    }
    
    func post(_ category:Category, _ subtitle:String?, _ body:String?=nil, _ zid:ZitiIdentity?=nil, _ completionHandler: (()->Void)?=nil) {
        zLog.info("Attempting to post \(category) notification, subitile:\(subtitle as Any), body:\(body as Any), zid:\(zid?.name as Any)")
        
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            zLog.debug("Notification settings: \(settings.debugDescription)")
            
            guard settings.authorizationStatus == .authorized else {
                zLog.warn("Not authorized to send nottifications")
                completionHandler?()
                return
            }
            
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = category.rawValue
            content.title = ProviderConfig().localizedDescription
            
            if let subtitle = subtitle { content.subtitle = subtitle }
            if let body = body { content.body = body }
            if let zid = zid {
                content.userInfo["zid"] = zid.id
            }
            
            let request = UNNotificationRequest(identifier: "ZitiNotification-\(category.rawValue)", content: content, trigger: nil)
            center.add(request) { error in
                if let error = error {
                    zLog.error("Unble to schedule request: \(error.localizedDescription)")
                }
                completionHandler?()
            }
        }
    }
}
