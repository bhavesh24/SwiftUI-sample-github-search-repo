//
//  ContentView.swift
//  SwiftUISampleApp
//
//  Created by Bhavesh on 18/11/23.
//

import SwiftUI

struct RepoView: View {
    @StateObject var repoViewModel = RepoViewModel()
    
    var body: some View {
        NavigationStack {
            if repoViewModel.error.isEmpty {
                List {
                    ForEach($repoViewModel.repos) { $item in
                        RepoRow(item: item)
                    }
                }.navigationTitle("Repos")
            } else {
                Text("We are facing some issues").navigationTitle("Repos")
            }
        }.searchable(text: $repoViewModel.keyword)
            .onSubmit(of: .search) {
                repoViewModel.getRepos(keyword: repoViewModel.keyword)
            }
    }
    
}

#Preview {
    RepoView(repoViewModel: RepoViewModel())
}
