import UIKit
import SwiftUI
import Combine

private nonisolated let sectionMain = 0

struct MatchListTableView: UIViewRepresentable {

    let viewModel: MatchListViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        context.coordinator.setUp(tableView)
        return tableView
    }

    func updateUIView(_ uiView: UITableView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITableViewDelegate {

        private let viewModel: MatchListViewModel
        private var dataSource: UITableViewDiffableDataSource<Int, Int>?
        private var cancellables = Set<AnyCancellable>()

        init(viewModel: MatchListViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        @objc private func handleRefresh(_ control: UIRefreshControl) {
            viewModel.retry()
        }

        func setUp(_ tableView: UITableView) {
            tableView.delegate = self
            tableView.register(
                MatchTableViewCell.self,
                forCellReuseIdentifier: MatchTableViewCell.reuseIdentifier
            )

            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
            tableView.refreshControl = refreshControl

            let source = UITableViewDiffableDataSource<Int, Int>(
                tableView: tableView
            ) { [weak self] (tableView: UITableView, indexPath: IndexPath, matchID: Int) in
                guard let cell = tableView.dequeueReusableCell(
                    withIdentifier: MatchTableViewCell.reuseIdentifier,
                    for: indexPath
                ) as? MatchTableViewCell else {
                    return UITableViewCell()
                }
                if let data = self?.viewModel.match(for: matchID) {
                    cell.configure(with: data)
                }
                return cell
            }
            dataSource = source

            viewModel.$displayedMatchIDs
                .receive(on: DispatchQueue.main)
                .sink { [weak self] ids in
                    self?.applySnapshot(ids: ids)
                }
                .store(in: &cancellables)

            viewModel.oddsUpdated
                .receive(on: DispatchQueue.main)
                .sink { [weak self] matchIDs in
                    self?.reconfigureItems(matchIDs)
                }
                .store(in: &cancellables)

            viewModel.$loadState
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    if tableView.refreshControl?.isRefreshing == true {
                        tableView.refreshControl?.endRefreshing()
                    }
                }
                .store(in: &cancellables)

            viewModel.loadNextPage()
        }

        // MARK: - Snapshot helpers

        private func applySnapshot(ids: [Int]) {
            guard let dataSource else { return }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([sectionMain])
            snapshot.appendItems(ids)
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        private func reconfigureItems(_ matchIDs: [Int]) {
            guard let dataSource else { return }
            var snapshot = dataSource.snapshot()
            let existing = Set(snapshot.itemIdentifiers)
            let toReconfigure = matchIDs.filter { existing.contains($0) }
            guard !toReconfigure.isEmpty else { return }
            snapshot.reconfigureItems(toReconfigure)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // MARK: - UITableViewDelegate

        func tableView(
            _ tableView: UITableView,
            willDisplay cell: UITableViewCell,
            forRowAt indexPath: IndexPath
        ) {
            if indexPath.row >= viewModel.displayedMatchIDs.count - 10 {
                viewModel.loadNextPage()
            }
        }
    }
}
