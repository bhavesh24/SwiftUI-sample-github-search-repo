//
//  StubURLProtocol.swift
//  SwiftUISampleAppTests
//

import Foundation
import os

/// Serves canned responses to `URLSession` requests in tests, keyed by URL, and counts
/// requests per URL. Tests use unique URLs, so stubs from tests running in parallel never clash.
final class StubURLProtocol: URLProtocol {
    enum Stub: Sendable {
        case success(statusCode: Int = 200, data: Data)
        case failure(URLError.Code)
    }

    private struct State {
        var stubs: [URL: Stub] = [:]
        var requestCounts: [URL: Int] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func stub(_ url: URL, with stub: Stub) {
        state.withLock { $0.stubs[url] = stub }
    }

    static func requestCount(for url: URL) -> Int {
        state.withLock { $0.requestCounts[url, default: 0] }
    }

    /// A session whose requests are all answered by this protocol.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = Self.state.withLock { state -> Stub? in
            state.requestCounts[url, default: 0] += 1
            return state.stubs[url]
        }
        switch stub {
        case let .success(statusCode, data):
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}
}
