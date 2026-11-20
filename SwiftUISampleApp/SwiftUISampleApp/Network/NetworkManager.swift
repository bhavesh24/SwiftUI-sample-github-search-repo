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
    /// Where downloaded images are cached. Injectable so tests can use their own directory.
    let imageCacheDirectory: URL

    init(
        session: URLSession,
        imageCacheDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCache", isDirectory: true)
    ) {
        self.session = session
        self.imageCacheDirectory = imageCacheDirectory
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

    /// Cached images younger than this are used without re-downloading.
    static let imageCacheMaxAge: TimeInterval = 24 * 60 * 60
    /// Cached images older than this are deleted by `pruneImageCache()`. Kept longer than
    /// `imageCacheMaxAge` so stale copies can still be shown when a refresh fails (e.g. offline).
    static let imageCacheRetention: TimeInterval = 7 * 24 * 60 * 60

    /// Returns the image data for `url`, from the on-disk cache if a fresh copy exists,
    /// otherwise by downloading it. If the download fails, falls back to a stale cached copy.
    /// Runs off the main actor and is cancelled with the calling task.
    func loadImageData(url: URL) async throws -> Data {
        let cacheURL = cacheFileURL(for: url)
        if let data = Self.cachedData(at: cacheURL, maxAge: Self.imageCacheMaxAge) {
            return data
        }
        do {
            try await download(url: url, toFile: cacheURL)
        } catch {
            if let staleData = Self.cachedData(at: cacheURL, maxAge: nil) {
                return staleData
            }
            throw error
        }
        return try Data(contentsOf: cacheURL)
    }

    /// Deletes cached images older than `imageCacheRetention`. Does blocking file I/O,
    /// so call it off the main thread.
    func pruneImageCache() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: imageCacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Self.imageCacheRetention)
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: file)
        }
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

        try fileManager.createDirectory(at: imageCacheDirectory, withIntermediateDirectories: true)
        // Stage under a unique name in the cache directory, then swap it into place in one step.
        let stagedURL = imageCacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
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
    func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return imageCacheDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Reads a cached regular file, if it exists and (when `maxAge` is given) is younger than `maxAge`.
    private static func cachedData(at file: URL, maxAge: TimeInterval?) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        if let maxAge, Date().timeIntervalSince(modified) >= maxAge {
            return nil
        }
        return try? Data(contentsOf: file)
    }
}
