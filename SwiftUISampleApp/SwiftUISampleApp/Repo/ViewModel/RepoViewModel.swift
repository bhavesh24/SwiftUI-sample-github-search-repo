//
//  RepoViewModel.swift
//  SwiftUISampleApp
//
//  Created by Bhavesh on 18/11/23.
//

import Foundation

@MainActor class RepoViewModel: ObservableObject {
    @Published var repos: [Repo] = []
    @Published var keyword: String = "" {
        didSet {
            getRepos(keyword: keyword)
        }
    }
    @Published var error: String = ""
    
    func getRepos(keyword: String) {
        Task {
            await getRepos(keyword: keyword)
        }
    }
    
    func getRepos(keyword: String) async {
        do {
            let data = try await NetworkManager.shared().getData(queryParams: [QueryParams.searchKey: keyword])
            let repoContainer = try JSONDecoder().decode(RepoContainer.self, from: data)
            repos = repoContainer.items ?? []
            error = ""
        } catch {
            if !keyword.isEmpty {
                self.error = error.localizedDescription
                repos = []
            }
        }
    }
}
