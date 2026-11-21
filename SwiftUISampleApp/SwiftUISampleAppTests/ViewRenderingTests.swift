//
//  ViewRenderingTests.swift
//  SwiftUISampleAppTests
//
//  Smoke tests that lay out each screen state, so view bodies are exercised in unit runs.
//  Rows use owners without avatar URLs, so nothing reaches the network.
//

import SwiftUI
import Testing
import UIKit
@testable import SwiftUISampleApp

@MainActor
struct ViewRenderingTests {

    @Test func rendersRowWithoutOwner() {
        let view = render(RepoRow(item: Repo(id: 1, full_name: "owner/repo")))
        #expect(view.bounds.width > 0)
    }

    @Test func rendersResultsList() {
        let viewModel = RepoViewModel()
        viewModel.repos = [Repo(id: 1, full_name: "a/one"), Repo(id: 2, full_name: "b/two")]

        let view = render(RepoView(repoViewModel: viewModel))

        #expect(view.bounds.width > 0)
    }

    @Test func rendersErrorAndLoadingStates() {
        let viewModel = RepoViewModel()
        viewModel.error = "Something went wrong"
        viewModel.isLoading = true

        let view = render(RepoView(repoViewModel: viewModel))

        #expect(view.bounds.width > 0)
    }

    @Test func viewControllerEmbedsRepoView() throws {
        let controller = ViewController()

        controller.loadViewIfNeeded()

        let hosting = try #require(controller.children.first as? UIHostingController<RepoView>)
        #expect(hosting.view.superview === controller.view)
        #expect(hosting.safeAreaRegions == [])
    }

    // MARK: - Helpers

    /// Hosts `view` in an on-screen window and lays it out.
    @discardableResult
    private func render(_ view: some View) -> UIView {
        let hosting = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.isHidden = true
        return hosting.view
    }
}
