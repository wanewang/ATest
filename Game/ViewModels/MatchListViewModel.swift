import Foundation
import Combine

final class MatchListViewModel: ObservableObject {

    enum LoadState {
        case idle
        case loading
        case loaded
        case failed(Error)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var displayedMatchIDs: [Int] = []

    private(set) var matchDataMap: [Int: MatchWithOdds] = [:]

    /// Emits matchIDs whose odds changed — subscribers reconfigure only those cells.
    let oddsUpdated = PassthroughSubject<[Int], Never>()

    private var allMatches: [MatchWithOdds] = []
    private var currentPage = 0
    private var hasMorePages = true
    private let pageSize = 40

    private var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    private let dataProvider: MatchDataProviding
    private var cancellables = Set<AnyCancellable>()

    init(dataProvider: MatchDataProviding) {
        self.dataProvider = dataProvider
        subscribeToOddsStream()
    }

    deinit {
        dataProvider.disconnectOddsStream()
    }

    // MARK: - Pagination

    func loadNextPage() {
        guard !isLoading, hasMorePages else { return }

        if allMatches.isEmpty {
            fetchAll()
        } else {
            appendNextPage()
        }
    }

    // MARK: - Real-time odds

    private func subscribeToOddsStream() {
        dataProvider.oddsStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] oddsBatch in
                self?.applyOddsUpdates(oddsBatch)
            }
            .store(in: &cancellables)
    }

    private func applyOddsUpdates(_ batch: [MatchOdds]) {
        var changedIDs: [Int] = []
        for newOdds in batch {
            guard let existing = matchDataMap[newOdds.matchID] else { continue }
            let updated = MatchWithOdds(match: existing.match, odds: newOdds)
            matchDataMap[newOdds.matchID] = updated
            if let index = allMatches.firstIndex(where: { $0.match.matchID == newOdds.matchID }) {
                allMatches[index] = updated
            }
            changedIDs.append(newOdds.matchID)
        }
        if !changedIDs.isEmpty {
            oddsUpdated.send(changedIDs)
        }
    }

    func match(for id: Int) -> MatchWithOdds? {
        matchDataMap[id]
    }

    // MARK: - Private

    func retry() {
        allMatches = []
        hasMorePages = true
        fetchAll(reset: true)
    }

    private func fetchAll(reset: Bool = false) {
        Task { @MainActor in
            loadState = .loading
        }

        dataProvider.fetchMatchesWithOdds(reset: reset)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let error) = completion {
                        self.loadState = .failed(error)
                    }
                },
                receiveValue: { [weak self] matches in
                    guard let self else { return }
                    self.matchDataMap = [:]
                    self.displayedMatchIDs = []
                    self.currentPage = 0
                    self.allMatches = matches
                    for m in matches {
                        self.matchDataMap[m.match.matchID] = m
                    }
                    self.appendNextPage()
                    self.loadState = .loaded
                    self.dataProvider.connectOddsStream(matchIDs: self.allMatches.map(\.match.matchID))
                }
            )
            .store(in: &cancellables)
    }

    private func appendNextPage() {
        let start = currentPage * pageSize
        guard start < allMatches.count else {
            hasMorePages = false
            return
        }
        let end = min(start + pageSize, allMatches.count)
        let page = allMatches[start..<end]

        displayedMatchIDs.append(contentsOf: page.map(\.match.matchID))
        currentPage += 1

        if end >= allMatches.count {
            hasMorePages = false
        }
    }
}
