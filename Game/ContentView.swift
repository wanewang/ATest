//
//  ContentView.swift
//  Game
//
//  Created by Wane on 2026/2/17.
//

import SwiftUI

struct ContentView: View {

    @StateObject private var viewModel = MatchListViewModel(
        dataProvider: MatchDataProvider(networkService: MockNetworkService())
    )

    var body: some View {
        ZStack {
            MatchListTableView(viewModel: viewModel)
                .ignoresSafeArea()

            switch viewModel.loadState {
            case .idle, .loaded:
                EmptyView()
            case .loading:
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            case .failed(let error):
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(error.localizedDescription)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        viewModel.retry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
    }
}

#Preview {
    ContentView()
}
