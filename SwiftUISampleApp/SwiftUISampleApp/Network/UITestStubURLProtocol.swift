//
//  UITestStubURLProtocol.swift
//  SwiftUISampleApp
//
//  Debug-only canned network responses for UI tests. UI tests launch the app with
//  `launchArgument`, and `NetworkManager.makeDefaultSession` routes every request here,
//  so the tests never touch the live GitHub API.
//

#if DEBUG
import UIKit

final class UITestStubURLProtocol: URLProtocol {
    static let launchArgument = "-UITestStubNetwork"

    /// The image cache used in stub mode, kept apart from the real `ImageCache` and emptied
    /// at every launch by `NetworkManager.makeShared`.
    static let imageCacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UITestImageCache", isDirectory: true)

    static let avatarHost = "avatars.stub"
    static let brokenAvatarHost = "avatars-broken.stub"
    static let resultCount = 10
    static let slowDelay: TimeInterval = 1.5

    /// Search keywords with special behavior. Any other keyword returns `resultCount`
    /// repos named `stub/<keyword>-<n>`, each with its own avatar.
    enum Keyword {
        static let error = "error"
        static let empty = "empty"
        static let slow = "slow"
        static let sharedOwner = "shared-owner"
        static let brokenAvatar = "broken-avatar"
    }

    struct Response: Sendable {
        var statusCode: Int
        var data: Data
        var delay: TimeInterval = 0
    }

    // MARK: - Responses

    static func response(for url: URL) -> Response {
        switch url.host {
        case avatarHost:
            return Response(statusCode: 200, data: avatarPNGData())
        case brokenAvatarHost:
            return Response(statusCode: 404, data: Data("Not Found".utf8))
        default:
            break
        }

        guard url.absoluteString.hasPrefix(NetworkConstants.baseUrl) else {
            return Response(statusCode: 404, data: Data("Not Found".utf8))
        }
        let keyword = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == QueryParams.searchKey }?.value ?? ""

        switch keyword {
        case Keyword.error:
            return Response(statusCode: 500, data: Data(#"{"message":"Stubbed server error"}"#.utf8))
        case Keyword.empty:
            return Response(statusCode: 200, data: searchResultsData(repos: []))
        case Keyword.slow:
            return Response(statusCode: 200, data: searchResultsData(repos: repos(for: keyword)), delay: slowDelay)
        default:
            return Response(statusCode: 200, data: searchResultsData(repos: repos(for: keyword)))
        }
    }

    static func repos(for keyword: String) -> [Repo] {
        (1 ... resultCount).map { number in
            let avatarURL = switch keyword {
            case Keyword.sharedOwner: "https://\(avatarHost)/u/shared"
            case Keyword.brokenAvatar: "https://\(brokenAvatarHost)/u/\(number)"
            default: "https://\(avatarHost)/u/\(number)"
            }
            return Repo(
                id: number,
                name: "\(keyword)-\(number)",
                full_name: "stub/\(keyword)-\(number)",
                owner: owner(login: "stub-owner-\(number)", avatarURL: avatarURL)
            )
        }
    }

    /// A search API response body wrapping `repos`.
    static func searchResultsData(repos: [Repo]) -> Data {
        let items = (try? JSONEncoder().encode(repos)) ?? Data("[]".utf8)
        return Data(#"{"total_count":\#(repos.count),"incomplete_results":false,"items":"#.utf8)
            + items
            + Data("}".utf8)
    }

    /// `Owner` has no memberwise initializer, so build it the way the API does: from JSON.
    private static func owner(login: String, avatarURL: String) -> Owner? {
        let json: [String: Any] = ["login": login, "avatar_url": avatarURL]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(Owner.self, from: data)
    }

    /// A solid-color square PNG, drawn with Core Graphics so it's safe off the main thread.
    static func avatarPNGData(side: Int = 16) -> Data {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { return Data() }
        return UIImage(cgImage: image).pngData() ?? Data()
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = Self.response(for: url)
        if stub.delay > 0 {
            // Runs on URLSession's loader thread, not the main thread.
            Thread.sleep(forTimeInterval: stub.delay)
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
