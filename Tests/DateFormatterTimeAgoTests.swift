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

class DateFormatterTimeAgoTests: XCTestCase {

    let formatter = DateFormatter()

    // MARK: - Edge cases

    func testTimeSince_zeroInterval() {
        XCTAssertEqual(formatter.timeSince(0), "never")
    }

    func testTimeSince_negativeInterval() {
        XCTAssertEqual(formatter.timeSince(-100), "never")
    }

    // MARK: - Seconds

    func testTimeSince_justNow() {
        let twoSecondsAgo = Date().timeIntervalSince1970 - 2
        XCTAssertEqual(formatter.timeSince(twoSecondsAgo), "just now")
    }

    func testTimeSince_secondsAgo() {
        let tenSecondsAgo = Date().timeIntervalSince1970 - 10
        XCTAssertEqual(formatter.timeSince(tenSecondsAgo), "10 seconds ago")
    }

    // MARK: - Minutes

    func testTimeSince_aMinuteAgo() {
        let oneMinuteAgo = Date().timeIntervalSince1970 - 65
        XCTAssertEqual(formatter.timeSince(oneMinuteAgo), "a minute ago")
    }

    func testTimeSince_minutesAgo() {
        let fiveMinutesAgo = Date().timeIntervalSince1970 - (5 * 60)
        XCTAssertEqual(formatter.timeSince(fiveMinutesAgo), "5 minutes ago")
    }

    // MARK: - Hours

    func testTimeSince_anHourAgo() {
        let oneHourAgo = Date().timeIntervalSince1970 - (65 * 60)
        XCTAssertEqual(formatter.timeSince(oneHourAgo), "an hour ago")
    }

    func testTimeSince_hoursAgo() {
        let threeHoursAgo = Date().timeIntervalSince1970 - (3 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(threeHoursAgo), "3 hours ago")
    }

    // MARK: - Days

    func testTimeSince_yesterday() {
        let oneDayAgo = Date().timeIntervalSince1970 - (26 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(oneDayAgo), "yesterday")
    }

    func testTimeSince_daysAgo() {
        let threeDaysAgo = Date().timeIntervalSince1970 - (3 * 24 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(threeDaysAgo), "3 days ago")
    }

    // MARK: - Weeks

    func testTimeSince_lastWeek() {
        let eightDaysAgo = Date().timeIntervalSince1970 - (8 * 24 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(eightDaysAgo), "last week")
    }

    func testTimeSince_weeksAgo() {
        let threeWeeksAgo = Date().timeIntervalSince1970 - (21 * 24 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(threeWeeksAgo), "3 weeks ago")
    }

    // MARK: - Months

    func testTimeSince_lastMonth() {
        let fiveWeeksAgo = Date().timeIntervalSince1970 - (35 * 24 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(fiveWeeksAgo), "last month")
    }

    func testTimeSince_monthsAgo() {
        let threeMonthsAgo = Date().timeIntervalSince1970 - (90 * 24 * 60 * 60)
        let result = formatter.timeSince(threeMonthsAgo)
        // Could be 2 or 3 months depending on calendar month lengths
        XCTAssertTrue(result.hasSuffix("months ago"), "Expected 'N months ago' but got '\(result)'")
    }

    // MARK: - Years

    func testTimeSince_lastYear() {
        let fourteenMonthsAgo = Date().timeIntervalSince1970 - (400 * 24 * 60 * 60)
        XCTAssertEqual(formatter.timeSince(fourteenMonthsAgo), "last year")
    }

    func testTimeSince_yearsAgo() {
        let threeYearsAgo = Date().timeIntervalSince1970 - (3 * 365 * 24 * 60 * 60)
        let result = formatter.timeSince(threeYearsAgo)
        XCTAssertTrue(result.hasSuffix("years ago"), "Expected 'N years ago' but got '\(result)'")
    }
}
