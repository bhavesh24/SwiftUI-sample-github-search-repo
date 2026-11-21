//
//  RepoViewModel.swift
//  SwiftUISampleApp
//
//  Created by Bhavesh on 18/11/23.
//

import Foundation

@MainActor final class RepoViewModel: ObservableObject {
    @Published var repos: [Repo] = []
    @Published var keyword: String = ""
    @Published var error: String = ""
    @Published var isLoading = false
    
    /// The search started by `getRepos(keyword:)`. Readable so tests can await it.
    private(set) var loadTask: Task<Void, Never>?

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }
    
    func getRepos(keyword: String) {
        loadTask?.cancel()
        loadTask = Task {
            await getRepos(keyword: keyword)
        }
    }
    
    func getRepos(keyword: String) async {
        guard !keyword.isEmpty else {
            repos = []
            error = ""
            isLoading = false
            return
        }
        
        isLoading = true
        
        do {
            let data = try await networkManager.getData(queryParams: [QueryParams.searchKey: keyword])
            guard !Task.isCancelled else { return }
            let repoContainer = try JSONDecoder().decode(RepoContainer.self, from: data)
            repos = repoContainer.items ?? []
            error = ""
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            repos = []
        }
        isLoading = false
    }
}
