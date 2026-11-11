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
            ZStack {
                Group {
                    if repoViewModel.error.isEmpty {
                        List {
                            ForEach(repoViewModel.repos) { item in
                                RepoRow(item: item)
                            }
                        }
                        .contentMargins(.top, 0, for: .scrollContent)
                    } else {
                        Text("We are facing some issues")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                }
                
                if repoViewModel.isLoading {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                }
            }
            .navigationTitle("Repos")
            .navigationBarTitleDisplayMode(.inline)
        }.searchable(text: $repoViewModel.keyword)
            .onSubmit(of: .search) {
                repoViewModel.getRepos(keyword: repoViewModel.keyword)
            }
    }
}

#Preview {
    RepoView(repoViewModel: RepoViewModel())
}
