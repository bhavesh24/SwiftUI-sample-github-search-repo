//
//  RepoSearchUITests.swift
//  SwiftUISampleAppUITests
//
//  End-to-end checks of the search screen. The app is launched with `-UITestStubNetwork`,
//  so every request is answered by `UITestStubURLProtocol` (Debug builds only) and the
//  tests are deterministic and need no network. Special search keywords:
//    error, empty, slow, shared-owner, broken-avatar; anything else returns 10 repos
//    named "stub/<keyword>-<n>".
//

import XCTest

final class RepoSearchUITests: XCTestCase {

    /// Must match `UITestStubURLProtocol.launchArgument` (the UI test target can't import the app).
    private static let stubNetworkArgument = "-UITestStubNetwork"
    private static let errorMessage = "We are facing some issues"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The app opens on an empty search screen.
    @MainActor
    func testLaunchShowsEmptySearchScreen() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Repos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertEqual(app.cells.count, 0)
    }

    /// A search shows its results, and every visible row's avatar loads.
    @MainActor
    func testSearchShowsResultsWithOwnerAvatars() throws {
        let app = launchApp()

        search(app, for: "swift")
        waitForResults(in: app)

        XCTAssertTrue(app.staticTexts["stub/swift-1"].exists)
        XCTAssertTrue(app.staticTexts["stub/swift-2"].exists)
        waitForVisibleAvatarsToLoad(in: app)
    }

    /// Many rows share one owner, so their avatars load the same cache file at the same time.
    @MainActor
    func testRowsSharingAnOwnerAllShowAvatars() throws {
        let app = launchApp()

        search(app, for: "shared-owner")
        waitForResults(in: app)

        waitForVisibleAvatarsToLoad(in: app)
    }

    /// Searching again reuses cached avatars, so they appear almost at once.
    @MainActor
    func testRepeatSearchLoadsAvatarsFromCache() throws {
        let app = launchApp()
        search(app, for: "swiftui")
        waitForResults(in: app)
        waitForVisibleAvatarsToLoad(in: app)

        search(app, for: "swiftui")
        waitForResults(in: app)

        waitForVisibleAvatarsToLoad(in: app, timeout: 5)
    }

    /// A server error shows the error message instead of the list.
    @MainActor
    func testServerErrorShowsErrorMessage() throws {
        let app = launchApp()

        search(app, for: "error")

        XCTAssertTrue(app.staticTexts[Self.errorMessage].waitForExistence(timeout: 10))
        XCTAssertEqual(app.cells.count, 0)
    }

    /// After an error, a successful search shows results and hides the error.
    @MainActor
    func testSearchAfterErrorShowsResults() throws {
        let app = launchApp()
        search(app, for: "error")
        XCTAssertTrue(app.staticTexts[Self.errorMessage].waitForExistence(timeout: 10))

        search(app, for: "recovered")
        waitForResults(in: app)

        XCTAssertTrue(app.staticTexts["stub/recovered-1"].exists)
        XCTAssertFalse(app.staticTexts[Self.errorMessage].exists)
    }

    /// A search with no matches shows an empty list and no error.
    @MainActor
    func testEmptyResultsShowNoRows() throws {
        let app = launchApp()
        search(app, for: "swift")
        waitForResults(in: app)

        search(app, for: "empty")

        let rowsGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.cells)
        XCTAssertEqual(XCTWaiter().wait(for: [rowsGone], timeout: 10), .completed, "old rows were not cleared")
        XCTAssertFalse(app.staticTexts[Self.errorMessage].exists)
    }

    /// A spinner shows while a search is in progress and goes away when results arrive.
    @MainActor
    func testSpinnerShowsWhileSearching() throws {
        let app = launchApp()

        search(app, for: "slow")

        let spinner = app.activityIndicators.firstMatch
        XCTAssertTrue(spinner.waitForExistence(timeout: 5), "no spinner while loading")
        waitForResults(in: app)
        let spinnerGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: spinner)
        XCTAssertEqual(XCTWaiter().wait(for: [spinnerGone], timeout: 5), .completed, "spinner stayed after loading")
    }

    /// When an avatar can't be downloaded, the row keeps its placeholder.
    @MainActor
    func testFailedAvatarKeepsPlaceholder() throws {
        let app = launchApp()

        search(app, for: "broken-avatar")
        waitForResults(in: app)

        let placeholders = app.descendants(matching: .any).matching(identifier: "avatar.placeholder")
        let loaded = app.descendants(matching: .any).matching(identifier: "avatar.loaded")
        XCTAssertTrue(placeholders.firstMatch.waitForExistence(timeout: 5))
        // Give the avatar downloads time to fail; none may turn into a loaded image.
        let anyLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in loaded.count > 0 }, object: nil)
        anyLoaded.isInverted = true
        XCTAssertEqual(XCTWaiter().wait(for: [anyLoaded], timeout: 3), .completed, "a broken avatar was shown as loaded")
        XCTAssertGreaterThanOrEqual(placeholders.count, 3)
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(Self.stubNetworkArgument)
        app.launch()
        return app
    }

    /// Types `keyword` into the search field, replacing any previous text, and submits it.
    @MainActor
    private func search(_ app: XCUIApplication, for keyword: String) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "search field not found")
        searchField.tap()
        if let current = searchField.value as? String, !current.isEmpty, current != searchField.placeholderValue {
            searchField.buttons["Clear text"].firstMatch.tap()
        }
        searchField.typeText(keyword + "\n")
    }

    @MainActor
    private func waitForResults(in app: XCUIApplication, timeout: TimeInterval = 10) {
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: timeout), "no results")
    }

    /// Waits until several avatars are loaded and none of the visible ones is still a placeholder.
    @MainActor
    private func waitForVisibleAvatarsToLoad(in app: XCUIApplication, timeout: TimeInterval = 10) {
        let loaded = app.descendants(matching: .any).matching(identifier: "avatar.loaded")
        let placeholders = app.descendants(matching: .any).matching(identifier: "avatar.placeholder")
        let allLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in loaded.count >= 3 && placeholders.count == 0 },
            object: nil
        )
        let result = XCTWaiter().wait(for: [allLoaded], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "avatars didn't all load within \(timeout)s: \(loaded.count) loaded, \(placeholders.count) placeholders"
        )
    }
}
