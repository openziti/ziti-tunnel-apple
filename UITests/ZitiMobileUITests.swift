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

/// The simulator keeps the app's data between runs, so tests don't assume a fresh install
final class ZitiMobileUITests: XCTestCase {
    private var app:XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Launches the app, allows its permission prompts (notifications, and on a device the VPN configuration) and closes
    /// Get Started, shown when there are no identities. While a prompt is up the app stays inactive, so it doesn't handle links
    private func launch(_ arguments:[String] = []) {
        app.launchArguments = arguments
        app.launch()
        let allow = springboard.alerts.buttons["Allow"]
        var answered = 0
        while answered < 3, allow.waitForExistence(timeout: 5) {
            allow.tap()
            answered += 1
        }
        let getStarted = app.navigationBars["Get Started"]
        if getStarted.waitForExistence(timeout: 5) {
            getStarted.buttons["Done"].tap()
        }
    }

    func testAddIdentityRow() {
        launch()
        XCTAssertTrue(app.cells.staticTexts["Add Identity"].waitForExistence(timeout: 5))
    }

    // MARK: - Managed app configuration

    /// Not contacted: a managed network is added as a pending identity, which enrolls only when tapped
    private static let managedHost = "managed.example.com"

    /// The managed app configuration an MDM writes, passed as a launch argument. That covers launch only: an argument
    /// doesn't post the change notification an MDM update does
    private static let managedArguments = ["-com.apple.configuration.managed",
        "{networks=({controller=\"https://\(managedHost)\";provider=alpha;type=cert;});disableAddIdentity=1;disableRemoveIdentity=1;}"]

    private var managedIdentity:XCUIElement {
        return app.cells.staticTexts[ZitiMobileUITests.managedHost].firstMatch
    }

    /// Forget is the last row of an identity's details, so it may need scrolling to
    private var forgetButton:XCUIElement {
        app.tables.firstMatch.swipeUp()
        return app.buttons["Forget This Identity"]
    }

    private func waitForRemoval(_ element:XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: 5) == .completed
    }

    /// Forgets the managed network's identity (restrictions are lifted without the configuration), so the next
    /// launch with it adds a new one
    private func forgetManagedIdentity() {
        managedIdentity.tap()
        forgetButton.tap()
        app.alerts["Are you sure?"].buttons["OK"].tap()
        XCTAssertTrue(waitForRemoval(managedIdentity))
    }

    func testManagedNetworkAndRestrictions() {
        // left by a run that didn't finish
        launch()
        if managedIdentity.waitForExistence(timeout: 2) {
            forgetManagedIdentity()
        }
        app.terminate()

        launch(ZitiMobileUITests.managedArguments)
        XCTAssertTrue(managedIdentity.waitForExistence(timeout: 5))
        XCTAssertFalse(app.cells.staticTexts["Add Identity"].exists)

        managedIdentity.tap()
        XCTAssertTrue(app.buttons["Enroll This Identity"].waitForExistence(timeout: 5))
        XCTAssertFalse(forgetButton.exists)
    }

    func testManagedLinkRefused() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("Opening a link needs iOS 16.4") }
        launch(ZitiMobileUITests.managedArguments)
        XCTAssertTrue(managedIdentity.waitForExistence(timeout: 5))

        app.open(URL(string: "ziti://enroll?controller=https://other.example.com")!)
        let alert = app.alerts["Unable to add identity"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Adding identities is turned off by your organization."].exists)
        alert.buttons["OK"].tap()
        XCTAssertFalse(app.cells.staticTexts["other.example.com"].exists)
    }

    func testRestrictionsLiftWithoutConfiguration() {
        launch(ZitiMobileUITests.managedArguments)
        XCTAssertTrue(managedIdentity.waitForExistence(timeout: 5))
        app.terminate()

        launch()
        XCTAssertTrue(app.cells.staticTexts["Add Identity"].waitForExistence(timeout: 5))
        // also leaves the simulator without it for the next run
        forgetManagedIdentity()
    }
}
