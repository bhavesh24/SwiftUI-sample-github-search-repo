//
//  RepoViewModelTests.swift
//  SwiftUISampleAppTests
//

import Foundation
import Testing
@testable import SwiftUISampleApp

/// Tests for the search screen's state. Searches go through `StubURLProtocol` with a unique
/// keyword per test, so tests never hit the network and can run in parallel.
@MainActor
final class RepoViewModelTests {
    let cacheDirectory: URL
    let manager: NetworkManager

    init() {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepoViewModelTests-\(UUID().uuidString)", isDirectory: true)
        manager = NetworkManager(session: StubURLProtocol.makeSession(), imageCacheDirectory: cacheDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    @Test func startsEmpty() {
        let viewModel = RepoViewModel(networkManager: manager)

        #expect(viewModel.repos.isEmpty)
        #expect(viewModel.keyword.isEmpty)
        #expect(viewModel.error.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.loadTask == nil)
    }

    @Test func successfulSearchShowsRepos() async throws {
        let keyword = try stubSearch(.success(data: Self.resultsJSON(names: ["a/one", "b/two"])))
        let viewModel = RepoViewModel(networkManager: manager)

        await viewModel.getRepos(keyword: keyword)

        #expect(viewModel.repos.map(\.full_name) == ["a/one", "b/two"])
        #expect(viewModel.error.isEmpty)
        #expect(!viewModel.isLoading)
    }

    @Test func missingItemsShowsNoRepos() async throws {
        let keyword = try stubSearch(.success(data: Data(#"{"total_count":0}"#.utf8)))
        let viewModel = RepoViewModel(networkManager: manager)

        await viewModel.getRepos(keyword: keyword)

        #expect(viewModel.repos.isEmpty)
        #expect(viewModel.error.isEmpty)
    }

    @Test func serverErrorShowsErrorAndClearsRepos() async throws {
        let viewModel = RepoViewModel(networkManager: manager)
        let good = try stubSearch(.success(data: Self.resultsJSON(names: ["a/one"])))
        await viewModel.getRepos(keyword: good)
        #expect(viewModel.repos.count == 1)

        let bad = try stubSearch(.success(statusCode: 500, data: Data()))
        await viewModel.getRepos(keyword: bad)

        #expect(!viewModel.error.isEmpty)
        #expect(viewModel.repos.isEmpty)
        #expect(!viewModel.isLoading)
    }

    @Test func malformedJSONShowsError() async throws {
        let keyword = try stubSearch(.success(data: Data("not json".utf8)))
        let viewModel = RepoViewModel(networkManager: manager)

        await viewModel.getRepos(keyword: keyword)

        #expect(!viewModel.error.isEmpty)
        #expect(viewModel.repos.isEmpty)
    }

    @Test func successAfterErrorClearsError() async throws {
        let viewModel = RepoViewModel(networkManager: manager)
        await viewModel.getRepos(keyword: try stubSearch(.failure(.notConnectedToInternet)))
        #expect(!viewModel.error.isEmpty)

        await viewModel.getRepos(keyword: try stubSearch(.success(data: Self.resultsJSON(names: ["a/one"]))))

        #expect(viewModel.error.isEmpty)
        #expect(viewModel.repos.count == 1)
    }

    @Test func emptyKeywordResetsStateWithoutSearching() async throws {
        let viewModel = RepoViewModel(networkManager: manager)
        await viewModel.getRepos(keyword: try stubSearch(.failure(.notConnectedToInternet)))
        #expect(!viewModel.error.isEmpty)

        await viewModel.getRepos(keyword: "")

        #expect(viewModel.repos.isEmpty)
        #expect(viewModel.error.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(StubURLProtocol.requestCount(for: try NetworkManagerTests.searchURL(keyword: "")) == 0)
    }

    @Test func synchronousSearchRunsInATask() async throws {
        let keyword = try stubSearch(.success(data: Self.resultsJSON(names: ["a/one"])))
        let viewModel = RepoViewModel(networkManager: manager)

        startSearch(viewModel, keyword: keyword)
        #expect(viewModel.loadTask != nil)
        await viewModel.loadTask?.value

        #expect(viewModel.repos.map(\.full_name) == ["a/one"])
    }

    @Test func newSearchCancelsThePreviousOne() async throws {
        let first = try stubSearch(.success(data: Self.resultsJSON(names: ["first/repo"])))
        let second = try stubSearch(.success(data: Self.resultsJSON(names: ["second/repo"])))
        let viewModel = RepoViewModel(networkManager: manager)

        startSearch(viewModel, keyword: first)
        let firstTask = try #require(viewModel.loadTask)
        startSearch(viewModel, keyword: second)
        await firstTask.value
        await viewModel.loadTask?.value

        #expect(firstTask.isCancelled)
        #expect(viewModel.repos.map(\.full_name) == ["second/repo"])
        #expect(!viewModel.isLoading)
    }

    // MARK: - Helpers

    /// Calls the synchronous `getRepos(keyword:)` that the view uses. From async code the
    /// compiler would pick the async overload instead.
    private func startSearch(_ viewModel: RepoViewModel, keyword: String) {
        viewModel.getRepos(keyword: keyword)
    }

    /// Stubs a search for a fresh unique keyword and returns that keyword.
    private func stubSearch(_ stub: StubURLProtocol.Stub) throws -> String {
        let keyword = UUID().uuidString
        StubURLProtocol.stub(try NetworkManagerTests.searchURL(keyword: keyword), with: stub)
        return keyword
    }

    private static func resultsJSON(names: [String]) -> Data {
        let items = names.enumerated()
            .map { #"{"id":\#($0.offset + 1),"full_name":"\#($0.element)"}"# }
            .joined(separator: ",")
        return Data(#"{"total_count":\#(names.count),"incomplete_results":false,"items":[\#(items)]}"#.utf8)
    }
}
