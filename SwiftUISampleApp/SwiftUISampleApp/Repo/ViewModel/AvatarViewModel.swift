//
//  AvatarViewModel.swift
//  SwiftUISampleApp
//

import UIKit
import os

@MainActor final class AvatarViewModel: ObservableObject {
    @Published var image: UIImage?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SwiftUISampleApp",
        category: "AvatarViewModel"
    )

    /// Pixel size requested from GitHub and used for the decoded thumbnail
    /// (32pt avatar at @3x).
    static let pixelSize = 96

    private let networkManager: NetworkManager
    private var loadedURLString: String?

    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }

    func loadImage(from urlString: String?) async {
        // Already showing this avatar (e.g. the row re-appeared): nothing to do.
        if urlString == loadedURLString, image != nil { return }

        // Drop the previous avatar right away so a stale image is never shown.
        image = nil
        loadedURLString = urlString

        guard let urlString, let url = Self.sizedAvatarURL(from: urlString) else { return }

        do {
            // Cache read and download run off the main actor, and the
            // download is cancelled when this task is cancelled.
            let data = try await networkManager.loadImageData(url: url)
            let side = CGFloat(Self.pixelSize)
            // `await` selects the async overload of byPreparingThumbnail(ofSize:)
            // (UIKit's prepareThumbnailOfSize:completionHandler:), which decodes on a
            // background thread. UIImage(data:) itself only wraps the bytes; it doesn't decode.
            let thumbnail = await UIImage(data: data)?
                .byPreparingThumbnail(ofSize: CGSize(width: side, height: side))
            guard !Task.isCancelled, loadedURLString == urlString else { return }
            image = thumbnail
        } catch is CancellationError {
            // Row went away; keep the placeholder.
        } catch let error as URLError where error.code == .cancelled {
            // Row went away; keep the placeholder.
        } catch {
            // Keep the placeholder, but leave a trace of real failures.
            Self.logger.error("Avatar load failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Asks GitHub's avatar server for a small image via its `s` (size) query parameter.
    static func sizedAvatarURL(from urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        var queryItems = (components.queryItems ?? []).filter { $0.name != "s" }
        queryItems.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components.queryItems = queryItems
        return components.url
    }
}
