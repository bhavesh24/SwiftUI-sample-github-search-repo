//
//  NetworkManager.swift
//  SwiftUISampleApp
//
//  Created by Bhavesh on 18/11/23.
//

import Foundation
import CryptoKit

enum NetworkConstants {
    static let baseUrl = "https://api.github.com/search/repositories"
}

enum NetworkError: Error {
    case invalidURL
    case invalidResponse(Data?, URLResponse?)
    
    var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse(_, _):
            return "We're facing some issues!"
        }
    }
}

enum QueryParams {
    static let searchKey = "q"
    static let order = "order"
    static let perPageEntries = "per_page"
    static let count = "count"
}

final class NetworkManager: Sendable {
    
    static let shared = NetworkManager(session: URLSession(configuration: .default))

    let session: URLSession?

    private init(session: URLSession) {
        self.session = session
    }
    
    public func getData(queryParams: [String: String]) async throws -> Data {
        let queryItems = queryParams.compactMap({ key, value in
            URLQueryItem(name: key, value: value)
        })
        var urlComps = URLComponents(string: NetworkConstants.baseUrl)
        urlComps?.queryItems = queryItems
        let url = urlComps?.url
        guard let url = url else {
            throw NetworkError.invalidURL
        }
        
        let request = URLRequest(url: url)
        do {
            let dataAndResponse = try await session?.data(for: request)
            if let data = dataAndResponse?.0,
               let httpResponse = dataAndResponse?.1 as? HTTPURLResponse,
               200 ..< 300 ~= httpResponse.statusCode {
                return data
            } else {
                throw NetworkError.invalidResponse(dataAndResponse?.0, dataAndResponse?.1)
            }
        } catch {
            throw error
        }
    }
    
    // MARK: - Image cache

    private static let imageCacheDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageCache", isDirectory: true)
    private static let imageCacheMaxAge: TimeInterval = 24 * 60 * 60

    /// Returns the image data for `url`, from the on-disk cache if a fresh copy exists,
    /// otherwise by downloading it. Runs off the main actor and is cancelled with the calling task.
    func loadImageData(url: URL) async throws -> Data {
        let cacheURL = Self.cacheFileURL(for: url)
        if let data = Self.freshCachedData(at: cacheURL) {
            return data
        }
        try await download(url: url, toFile: cacheURL)
        return try Data(contentsOf: cacheURL)
    }

    /// Downloads `url` and atomically places it at `file`, so concurrent
    /// downloads of the same URL never leave a partial or missing file.
    func download(url: URL, toFile file: URL) async throws {
        guard let session else { throw URLError(.unknown) }
        let (tempURL, response) = try await session.download(from: url)
        let fileManager = FileManager.default
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            try? fileManager.removeItem(at: tempURL)
            throw NetworkError.invalidResponse(nil, response)
        }

        try fileManager.createDirectory(at: Self.imageCacheDirectory, withIntermediateDirectories: true)
        // Stage under a unique name in the cache directory, then swap it into place in one step.
        let stagedURL = Self.imageCacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        try fileManager.moveItem(at: tempURL, to: stagedURL)
        do {
            do {
                try fileManager.moveItem(at: stagedURL, to: file)
            } catch CocoaError.fileWriteFileExists {
                _ = try fileManager.replaceItemAt(file, withItemAt: stagedURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }

    /// A cache file name derived from a hash of the full URL (host, path and query),
    /// so it is unique per URL and never empty.
    private static func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return imageCacheDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func freshCachedData(at file: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < imageCacheMaxAge else {
            return nil
        }
        return try? Data(contentsOf: file)
    }
}
