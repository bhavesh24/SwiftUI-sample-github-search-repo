//
//  AvatarViewModelTests.swift
//  SwiftUISampleAppTests
//

import Foundation
import Testing
import UIKit
@testable import SwiftUISampleApp

@MainActor
final class AvatarViewModelTests {
    let cacheDirectory: URL
    let manager: NetworkManager

    init() {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvatarViewModelTests-\(UUID().uuidString)", isDirectory: true)
        manager = NetworkManager(session: StubURLProtocol.makeSession(), imageCacheDirectory: cacheDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    // MARK: - Avatar URL sizing

    @Test func sizedAvatarURLRequestsDisplaySizeAndKeepsOtherParameters() throws {
        let url = try #require(AvatarViewModel.sizedAvatarURL(from: "https://avatars.test/u/1?v=4&s=460"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.filter { $0.name == "s" }.map(\.value) == [String(AvatarViewModel.pixelSize)])
        #expect(items.contains(URLQueryItem(name: "v", value: "4")))
    }

    // MARK: - Loading

    @Test func loadsImageFromURL() async throws {
        let urlString = uniqueAvatarURLString()
        try stub(urlString, with: .success(data: pngData()))
        let viewModel = AvatarViewModel(networkManager: manager)

        await viewModel.loadImage(from: urlString)

        #expect(viewModel.image != nil)
    }

    @Test func nilURLShowsPlaceholder() async {
        let viewModel = AvatarViewModel(networkManager: manager)

        await viewModel.loadImage(from: nil)

        #expect(viewModel.image == nil)
    }

    @Test func failedLoadShowsPlaceholder() async throws {
        let urlString = uniqueAvatarURLString()
        try stub(urlString, with: .failure(.notConnectedToInternet))
        let viewModel = AvatarViewModel(networkManager: manager)

        await viewModel.loadImage(from: urlString)

        #expect(viewModel.image == nil)
    }

    @Test func changingURLDropsPreviousImage() async throws {
        let first = uniqueAvatarURLString()
        let second = uniqueAvatarURLString()
        try stub(first, with: .success(data: pngData()))
        try stub(second, with: .failure(.notConnectedToInternet))
        let viewModel = AvatarViewModel(networkManager: manager)

        await viewModel.loadImage(from: first)
        #expect(viewModel.image != nil)

        await viewModel.loadImage(from: second)
        #expect(viewModel.image == nil, "the previous owner's avatar must not stay on screen")
    }

    @Test func reloadingSameURLKeepsCurrentImage() async throws {
        let urlString = uniqueAvatarURLString()
        try stub(urlString, with: .success(data: pngData()))
        let viewModel = AvatarViewModel(networkManager: manager)

        await viewModel.loadImage(from: urlString)
        let firstImage = try #require(viewModel.image)
        await viewModel.loadImage(from: urlString)

        #expect(viewModel.image === firstImage)
    }

    // MARK: - Helpers

    private func uniqueAvatarURLString() -> String {
        "https://avatars.test/u/\(UUID().uuidString)?v=4"
    }

    /// Stubs the URL the view model will actually request (with the size parameter added).
    private func stub(_ urlString: String, with stub: StubURLProtocol.Stub) throws {
        let url = try #require(AvatarViewModel.sizedAvatarURL(from: urlString))
        StubURLProtocol.stub(url, with: stub)
    }

    private func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
