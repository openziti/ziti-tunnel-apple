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

import XCTest
@testable import Ziti_Desktop_Edge

class DateFormatterTimeAgoTests: XCTestCase {

    let formatter = DateFormatter()

    /// A fixed moment and a UTC calendar, so results don't depend on the clock, the time zone or daylight saving
    private let now = Date(timeIntervalSince1970: 1_773_144_000) // 2026-03-10 12:00 UTC
    private let utc:Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let minute:TimeInterval = 60, hour:TimeInterval = 60 * 60, day:TimeInterval = 24 * 60 * 60

    private func timeSince(_ secondsAgo:TimeInterval) -> String {
        return formatter.timeSince(now.timeIntervalSince1970 - secondsAgo, now: now, calendar: utc)
    }

    private func timeSince(_ component:Calendar.Component, ago value:Int) -> String {
        let from = utc.date(byAdding: component, value: -value, to: now)!
        return formatter.timeSince(from.timeIntervalSince1970, now: now, calendar: utc)
    }

    // MARK: - Edge cases

    func testTimeSince_zeroInterval() {
        XCTAssertEqual(formatter.timeSince(0, now: now, calendar: utc), "never")
    }

    func testTimeSince_negativeInterval() {
        XCTAssertEqual(formatter.timeSince(-100, now: now, calendar: utc), "never")
    }

    func testTimeSince_usesTheGivenCalendar() {
        // 88 days back is 2 Gregorian months but 3 Islamic civil ones
        var islamic = Calendar(identifier: .islamicCivil)
        islamic.timeZone = utc.timeZone
        let from = now.timeIntervalSince1970 - 88 * day
        XCTAssertEqual(formatter.timeSince(from, now: now, calendar: utc), "2 months ago")
        XCTAssertEqual(formatter.timeSince(from, now: now, calendar: islamic), "3 months ago")
    }

    func testTimeSince_defaultsToNow() {
        // the real clock and time zone: well inside the range, so timing and daylight saving don't matter
        XCTAssertEqual(formatter.timeSince(Date().timeIntervalSince1970 - 2.5 * day), "2 days ago")
    }

    // MARK: - Seconds

    func testTimeSince_justNow() {
        XCTAssertEqual(timeSince(2), "just now")
    }

    func testTimeSince_secondsAgo() {
        XCTAssertEqual(timeSince(10), "10 seconds ago")
    }

    // MARK: - Minutes

    func testTimeSince_aMinuteAgo() {
        XCTAssertEqual(timeSince(65), "a minute ago")
    }

    func testTimeSince_minutesAgo() {
        XCTAssertEqual(timeSince(5 * minute), "5 minutes ago")
    }

    // MARK: - Hours

    func testTimeSince_anHourAgo() {
        XCTAssertEqual(timeSince(65 * minute), "an hour ago")
    }

    func testTimeSince_hoursAgo() {
        XCTAssertEqual(timeSince(3 * hour), "3 hours ago")
    }

    // MARK: - Days

    func testTimeSince_yesterday() {
        XCTAssertEqual(timeSince(26 * hour), "yesterday")
    }

    func testTimeSince_daysAgo() {
        XCTAssertEqual(timeSince(3 * day), "3 days ago")
    }

    // MARK: - Weeks

    func testTimeSince_lastWeek() {
        XCTAssertEqual(timeSince(8 * day), "last week")
    }

    func testTimeSince_weeksAgo() {
        XCTAssertEqual(timeSince(21 * day), "3 weeks ago")
    }

    // MARK: - Months

    func testTimeSince_lastMonth() {
        XCTAssertEqual(timeSince(35 * day), "last month")
    }

    func testTimeSince_monthsAgo() {
        XCTAssertEqual(timeSince(.month, ago: 3), "3 months ago")
    }

    // MARK: - Years

    func testTimeSince_lastYear() {
        XCTAssertEqual(timeSince(400 * day), "last year")
    }

    func testTimeSince_yearsAgo() {
        XCTAssertEqual(timeSince(.year, ago: 3), "3 years ago")
    }
}
