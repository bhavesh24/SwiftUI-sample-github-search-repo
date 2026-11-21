//
//  NetworkManagerTests.swift
//  SwiftUISampleAppTests
//

import Foundation
import Testing
@testable import SwiftUISampleApp

/// Tests for NetworkManager's image cache. Each test gets its own cache directory and unique
/// URLs answered by `StubURLProtocol`, so tests are independent and never hit the network.
final class NetworkManagerTests {
    let cacheDirectory: URL
    let manager: NetworkManager

    init() {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetworkManagerTests-\(UUID().uuidString)", isDirectory: true)
        manager = NetworkManager(session: StubURLProtocol.makeSession(), imageCacheDirectory: cacheDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    // MARK: - Cache file naming

    @Test func cacheFileNameIsUniquePerFullURL() throws {
        let urls = [
            "https://avatars.test/u/1?v=4",
            "https://avatars.test/u/1?v=5",   // same path, different query
            "https://other.test/u/1?v=4",     // same path and query, different host
            "https://avatars.test/x/1?v=4",   // same last path component
        ].map { URL(string: $0)! }

        let files = urls.map(manager.cacheFileURL(for:))

        #expect(Set(files).count == urls.count)
        #expect(manager.cacheFileURL(for: urls[0]) == files[0], "naming must be deterministic")
        for file in files {
            #expect(file.deletingLastPathComponent().path == cacheDirectory.path)
            #expect(file.lastPathComponent.count == 64, "SHA-256 hex digest")
        }
    }

    @Test func cacheFileForRootURLStaysInsideCacheDirectory() throws {
        let file = manager.cacheFileURL(for: URL(string: "https://example.test/")!)

        #expect(file.path != cacheDirectory.path)
        #expect(file.deletingLastPathComponent().path == cacheDirectory.path)
    }

    // MARK: - Loading

    @Test func downloadsOnceThenServesFromCache() async throws {
        let url = uniqueURL()
        let imageData = Data("image".utf8)
        StubURLProtocol.stub(url, with: .success(data: imageData))

        #expect(try await manager.loadImageData(url: url) == imageData)
        #expect(try await manager.loadImageData(url: url) == imageData)

        #expect(StubURLProtocol.requestCount(for: url) == 1)
        #expect(try Data(contentsOf: manager.cacheFileURL(for: url)) == imageData)
    }

    @Test func refreshesExpiredCacheFile() async throws {
        let url = uniqueURL()
        try writeCacheFile(for: url, data: Data("old".utf8), age: NetworkManager.imageCacheMaxAge + 60)
        StubURLProtocol.stub(url, with: .success(data: Data("new".utf8)))

        let data = try await manager.loadImageData(url: url)

        #expect(data == Data("new".utf8))
        #expect(StubURLProtocol.requestCount(for: url) == 1)
        #expect(try Data(contentsOf: manager.cacheFileURL(for: url)) == Data("new".utf8))
    }

    @Test func fallsBackToStaleCacheWhenRefreshFails() async throws {
        let url = uniqueURL()
        try writeCacheFile(for: url, data: Data("stale".utf8), age: 2 * 24 * 60 * 60)
        StubURLProtocol.stub(url, with: .failure(.notConnectedToInternet))

        let data = try await manager.loadImageData(url: url)

        #expect(data == Data("stale".utf8))
        #expect(StubURLProtocol.requestCount(for: url) == 1)
    }

    @Test func throwsWhenDownloadFailsAndNothingIsCached() async throws {
        let url = uniqueURL()
        StubURLProtocol.stub(url, with: .failure(.notConnectedToInternet))

        await #expect(throws: (any Error).self) {
            try await self.manager.loadImageData(url: url)
        }
        #expect(!FileManager.default.fileExists(atPath: manager.cacheFileURL(for: url).path))
    }

    @Test func doesNotCacheErrorResponses() async throws {
        let url = uniqueURL()
        StubURLProtocol.stub(url, with: .success(statusCode: 404, data: Data("Not Found".utf8)))

        await #expect(throws: NetworkError.self) {
            try await self.manager.loadImageData(url: url)
        }
        #expect(!FileManager.default.fileExists(atPath: manager.cacheFileURL(for: url).path))
    }

    @Test func concurrentLoadsOfSameURLAllSucceed() async throws {
        let url = uniqueURL()
        let imageData = Data((0 ..< 50_000).map { UInt8($0 % 251) })
        StubURLProtocol.stub(url, with: .success(data: imageData))
        let manager = self.manager

        let results = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0 ..< 20 {
                group.addTask { try await manager.loadImageData(url: url) }
            }
            return try await group.reduce(into: [Data]()) { $0.append($1) }
        }

        #expect(results.count == 20)
        #expect(results.allSatisfy { $0 == imageData })
        #expect(try Data(contentsOf: manager.cacheFileURL(for: url)) == imageData)
        // Only the final file remains: no leftover staging files.
        let contents = try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        #expect(contents == [manager.cacheFileURL(for: url).lastPathComponent])
    }

    // MARK: - Pruning

    @Test func pruneDeletesOnlyFilesPastRetention() throws {
        let expired = uniqueURL()
        let stale = uniqueURL()
        try writeCacheFile(for: expired, data: Data("expired".utf8), age: NetworkManager.imageCacheRetention + 60)
        try writeCacheFile(for: stale, data: Data("stale".utf8), age: NetworkManager.imageCacheMaxAge + 60)
        let subdirectory = cacheDirectory.appendingPathComponent("subdirectory", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try setAge(NetworkManager.imageCacheRetention + 60, of: subdirectory)

        manager.pruneImageCache()

        #expect(!FileManager.default.fileExists(atPath: manager.cacheFileURL(for: expired).path))
        #expect(FileManager.default.fileExists(atPath: manager.cacheFileURL(for: stale).path))
        #expect(FileManager.default.fileExists(atPath: subdirectory.path), "only regular files are pruned")
    }

    @Test func pruneWithoutCacheDirectoryDoesNothing() {
        manager.pruneImageCache()
        #expect(!FileManager.default.fileExists(atPath: cacheDirectory.path))
    }

    // MARK: - Repo search

    @Test func getDataReturnsBodyOfSuccessfulResponse() async throws {
        let keyword = UUID().uuidString
        let body = Data(#"{"items":[]}"#.utf8)
        StubURLProtocol.stub(try Self.searchURL(keyword: keyword), with: .success(data: body))

        let data = try await manager.getData(queryParams: [QueryParams.searchKey: keyword])

        #expect(data == body)
        #expect(StubURLProtocol.requestCount(for: try Self.searchURL(keyword: keyword)) == 1)
    }

    @Test func getDataThrowsInvalidResponseForErrorStatus() async throws {
        let keyword = UUID().uuidString
        let body = Data("rate limited".utf8)
        StubURLProtocol.stub(try Self.searchURL(keyword: keyword), with: .success(statusCode: 403, data: body))

        do {
            _ = try await manager.getData(queryParams: [QueryParams.searchKey: keyword])
            Issue.record("expected an error")
        } catch let NetworkError.invalidResponse(data, response) {
            #expect(data == body)
            #expect((response as? HTTPURLResponse)?.statusCode == 403)
        }
    }

    @Test func getDataRethrowsTransportErrors() async throws {
        let keyword = UUID().uuidString
        StubURLProtocol.stub(try Self.searchURL(keyword: keyword), with: .failure(.notConnectedToInternet))

        await #expect(throws: URLError.self) {
            try await self.manager.getData(queryParams: [QueryParams.searchKey: keyword])
        }
    }

    @Test func networkErrorDescriptions() {
        #expect(NetworkError.invalidURL.description == "Invalid URL")
        #expect(NetworkError.invalidResponse(nil, nil).description == "We're facing some issues!")
    }

    @Test func defaultSessionUsesStubOnlyWithLaunchArgument() {
        let stubbed = NetworkManager.makeDefaultSession(arguments: [UITestStubURLProtocol.launchArgument])
        let live = NetworkManager.makeDefaultSession(arguments: [])

        #expect(stubbed.configuration.protocolClasses?.first == UITestStubURLProtocol.self)
        #expect(live.configuration.protocolClasses?.first != UITestStubURLProtocol.self)
    }

    @Test func sharedInstanceInStubModeStartsWithEmptySeparateCache() throws {
        let stubCache = UITestStubURLProtocol.imageCacheDirectory
        try FileManager.default.createDirectory(at: stubCache, withIntermediateDirectories: true)
        try Data("old avatar".utf8).write(to: stubCache.appendingPathComponent("leftover"))

        let stubbed = NetworkManager.makeShared(arguments: [UITestStubURLProtocol.launchArgument])
        let live = NetworkManager.makeShared(arguments: [])

        #expect(stubbed.imageCacheDirectory == stubCache)
        #expect(!FileManager.default.fileExists(atPath: stubCache.path), "leftover avatars must be cleared")
        #expect(stubbed.session?.configuration.protocolClasses?.first == UITestStubURLProtocol.self)
        #expect(live.imageCacheDirectory.lastPathComponent == "ImageCache")
        #expect(live.session?.configuration.protocolClasses?.first != UITestStubURLProtocol.self)
    }

    // MARK: - Helpers

    /// The URL `getData` requests for a single-keyword search.
    static func searchURL(keyword: String) throws -> URL {
        var components = try #require(URLComponents(string: NetworkConstants.baseUrl))
        components.queryItems = [URLQueryItem(name: QueryParams.searchKey, value: keyword)]
        return try #require(components.url)
    }

    private func uniqueURL() -> URL {
        URL(string: "https://avatars.test/u/\(UUID().uuidString)?v=4")!
    }

    private func writeCacheFile(for url: URL, data: Data, age: TimeInterval) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let file = manager.cacheFileURL(for: url)
        try data.write(to: file)
        try setAge(age, of: file)
    }

    private func setAge(_ age: TimeInterval, of file: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-age)],
            ofItemAtPath: file.path
        )
    }
}
