//
//  RepoViewModel.swift
//  SwiftUISampleApp
//
//  Created by Bhavesh on 18/11/23.
//

import Foundation

@MainActor class RepoViewModel: ObservableObject {
    @Published var repos: [Repo] = []
    @Published var keyword: String = ""
    @Published var error: String = ""
    @Published var isLoading = false
    
    private var loadTask: Task<Void, Never>?
    
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
            let data = try await NetworkManager.shared().getData(queryParams: [QueryParams.searchKey: keyword])
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
