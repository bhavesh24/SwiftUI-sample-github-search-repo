//
//  UITestStubURLProtocolTests.swift
//  SwiftUISampleAppTests
//

import Foundation
import Testing
import UIKit
@testable import SwiftUISampleApp

/// The canned responses UI tests rely on. Uses a session whose only protocol is the stub,
/// so nothing reaches the network.
struct UITestStubURLProtocolTests {
    let session = NetworkManager.makeDefaultSession(arguments: [UITestStubURLProtocol.launchArgument])

    @Test func defaultKeywordReturnsReposWithDistinctAvatars() async throws {
        let (container, status) = try await search("swift")

        #expect(status == 200)
        let repos = try #require(container?.items)
        #expect(repos.count == UITestStubURLProtocol.resultCount)
        #expect(container?.total_count == UITestStubURLProtocol.resultCount)
        #expect(repos.first?.full_name == "stub/swift-1")
        #expect(Set(repos.compactMap(\.owner?.avatar_url)).count == repos.count)
        #expect(repos.allSatisfy { URL(string: $0.owner?.avatar_url ?? "")?.host == UITestStubURLProtocol.avatarHost })
    }

    @Test func sharedOwnerKeywordReusesOneAvatar() async throws {
        let (container, _) = try await search(UITestStubURLProtocol.Keyword.sharedOwner)

        let avatars = Set(try #require(container?.items).compactMap(\.owner?.avatar_url))
        #expect(avatars.count == 1)
    }

    @Test func brokenAvatarKeywordUsesFailingAvatarHost() async throws {
        let (container, _) = try await search(UITestStubURLProtocol.Keyword.brokenAvatar)

        let hosts = Set(try #require(container?.items).compactMap { URL(string: $0.owner?.avatar_url ?? "")?.host })
        #expect(hosts == [UITestStubURLProtocol.brokenAvatarHost])
    }

    @Test func emptyKeywordReturnsNoRepos() async throws {
        let (container, status) = try await search(UITestStubURLProtocol.Keyword.empty)

        #expect(status == 200)
        #expect(container?.items?.isEmpty == true)
    }

    @Test func errorKeywordReturnsServerError() async throws {
        let (container, status) = try await search(UITestStubURLProtocol.Keyword.error)

        #expect(status == 500)
        #expect(container?.items == nil)
    }

    @Test func slowKeywordIsDelayed() {
        let url = searchURL(UITestStubURLProtocol.Keyword.slow)

        let response = UITestStubURLProtocol.response(for: url)

        #expect(response.delay == UITestStubURLProtocol.slowDelay)
        #expect(response.statusCode == 200)
    }

    @Test func avatarRequestsReturnAPNG() async throws {
        let url = try #require(URL(string: "https://\(UITestStubURLProtocol.avatarHost)/u/1?s=96"))

        let (data, response) = try await session.data(from: url)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(UIImage(data: data) != nil)
    }

    @Test func brokenAvatarsAndUnknownURLsReturn404() async throws {
        for urlString in ["https://\(UITestStubURLProtocol.brokenAvatarHost)/u/1", "https://unknown.test/path"] {
            let url = try #require(URL(string: urlString))
            let (_, response) = try await session.data(from: url)
            #expect((response as? HTTPURLResponse)?.statusCode == 404, "\(urlString)")
        }
    }

    // MARK: - Helpers

    private func searchURL(_ keyword: String) -> URL {
        var components = URLComponents(string: NetworkConstants.baseUrl)!
        components.queryItems = [URLQueryItem(name: QueryParams.searchKey, value: keyword)]
        return components.url!
    }

    private func search(_ keyword: String) async throws -> (RepoContainer?, Int?) {
        let (data, response) = try await session.data(from: searchURL(keyword))
        let status = (response as? HTTPURLResponse)?.statusCode
        return (try? JSONDecoder().decode(RepoContainer.self, from: data), status)
    }
}
