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
        MatchListTableView(viewModel: viewModel)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
