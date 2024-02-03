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
        Text(item.full_name ?? "")
    }
}

#Preview {
    RepoRow(item: Repo(full_name: "SampleRepo"))
}
