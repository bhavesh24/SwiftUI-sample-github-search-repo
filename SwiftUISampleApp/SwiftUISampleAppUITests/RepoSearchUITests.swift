//
//  RepoSearchUITests.swift
//  SwiftUISampleAppUITests
//
//  End-to-end checks against the live GitHub API. They need network access, and the
//  unauthenticated search API allows about 10 searches a minute.
//

import XCTest

final class RepoSearchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A search shows results, and every visible row's avatar loads.
    @MainActor
    func testSearchShowsOwnerAvatars() throws {
        let app = launchApp()

        search(app, for: "swift")

        waitForVisibleAvatarsToLoad(in: app)
        attachScreenshot(of: app, named: "1-search-swift")
    }

    /// Many rows share one owner, so their avatars load the same cache file at the same time.
    @MainActor
    func testRowsSharingAnOwnerAllShowAvatars() throws {
        let app = launchApp()

        search(app, for: "user:apple")

        waitForVisibleAvatarsToLoad(in: app)
        attachScreenshot(of: app, named: "2-search-user-apple")
    }

    /// Searching again reuses cached avatars, so they appear almost at once.
    @MainActor
    func testRepeatSearchLoadsAvatarsFromCache() throws {
        let app = launchApp()
        search(app, for: "swiftui")
        waitForVisibleAvatarsToLoad(in: app)

        search(app, for: "swiftui")

        waitForVisibleAvatarsToLoad(in: app, timeout: 5)
        attachScreenshot(of: app, named: "3-repeat-search-swiftui")
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    @MainActor
    private func search(_ app: XCUIApplication, for keyword: String) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "search field not found")
        searchField.tap()
        if let current = searchField.value as? String, !current.isEmpty, current != searchField.placeholderValue {
            searchField.buttons["Clear text"].firstMatch.tap()
        }
        searchField.typeText(keyword + "\n")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20), "no results for \"\(keyword)\"")
    }

    /// Waits until several avatars are loaded and none of the visible ones is still a placeholder.
    @MainActor
    private func waitForVisibleAvatarsToLoad(in app: XCUIApplication, timeout: TimeInterval = 20) {
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

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
