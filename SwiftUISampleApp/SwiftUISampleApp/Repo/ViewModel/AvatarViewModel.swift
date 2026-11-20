//
//  AvatarViewModel.swift
//  SwiftUISampleApp
//

import UIKit

@MainActor final class AvatarViewModel: ObservableObject {
    @Published var image: UIImage?

    /// Pixel size requested from GitHub and used for the decoded thumbnail
    /// (32pt avatar at @3x).
    private static let pixelSize = 96

    private var loadedURLString: String?

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
            let data = try await NetworkManager.shared.loadImageData(url: url)
            let side = CGFloat(Self.pixelSize)
            // Decode off the main thread at display size.
            let thumbnail = await UIImage(data: data)?
                .byPreparingThumbnail(ofSize: CGSize(width: side, height: side))
            guard !Task.isCancelled, loadedURLString == urlString else { return }
            image = thumbnail
        } catch {
            // Keep the placeholder on failure or cancellation.
        }
    }

    /// Asks GitHub's avatar server for a small image via its `s` (size) query parameter.
    private static func sizedAvatarURL(from urlString: String) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        var queryItems = (components.queryItems ?? []).filter { $0.name != "s" }
        queryItems.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components.queryItems = queryItems
        return components.url
    }
}
