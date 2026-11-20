//
//  RepoRow.swift
//  SwiftUISampleApp
//
//  Created by Bhavesh on 18/11/23.
//

import SwiftUI

struct RepoRow: View {
    let item: Repo
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: item.owner?.avatar_url)
            Text(item.full_name ?? "")
        }
    }
}

private struct AvatarView: View {
    let urlString: String?
    @StateObject private var viewModel = AvatarViewModel()

    var body: some View {
        Group {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityElement()
        .accessibilityLabel("Owner avatar")
        .accessibilityIdentifier(viewModel.image == nil ? "avatar.placeholder" : "avatar.loaded")
        .task(id: urlString) {
            await viewModel.loadImage(from: urlString)
        }
    }
}

#Preview {
    RepoRow(item: Repo(full_name: "SampleRepo"))
}
