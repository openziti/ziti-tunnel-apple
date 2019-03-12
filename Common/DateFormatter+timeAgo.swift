//
//  ViewController+timeAgo.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/11/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

extension DateFormatter {
    func timeSince(_ fromTimeIntervalSince1970: TimeInterval) -> String {
        if fromTimeIntervalSince1970 <= 0 { return "never" }
        let calendar = Calendar.current
        let now = Date()
        let unitFlags: NSCalendar.Unit = [.second, .minute, .hour, .day, .weekOfYear, .month, .year]
        let from = Date(timeIntervalSince1970: fromTimeIntervalSince1970)
        let components = (calendar as NSCalendar).components(unitFlags, from:from, to:now, options:[])
        
        if let year = components.year, year >= 2 { return "\(year) years ago" }
        if let year = components.year, year >= 1 { return "last year" }
        if let month = components.month, month >= 2 { return "\(month) months ago" }
        if let month = components.month, month >= 1 { return "last month" }
        if let week = components.weekOfYear, week >= 2 { return "\(week) weeks ago" }
        if let week = components.weekOfYear, week >= 1 { return "last week" }
        if let day = components.day, day >= 2 { return "\(day) days ago" }
        if let day = components.day, day >= 1 { return "yesterday" }
        if let hour = components.hour, hour >= 2 { return "\(hour) hours ago" }
        if let hour = components.hour, hour >= 1 { return "an hour ago" }
        if let minute = components.minute, minute >= 2 { return "\(minute) minutes ago" }
        if let minute = components.minute, minute >= 1 { return "a minute ago" }
        if let second = components.second, second >= 3 { return "\(second) seconds ago" }
        return "just now"
    }
}
