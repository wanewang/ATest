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

    // MARK: - Real-time odds update hook

    func updateOdds(for matchID: Int, teamAOdds: Double, teamBOdds: Double) {
        guard let existing = matchDataMap[matchID] else { return }
        let newOdds = MatchOdds(matchID: matchID, teamAOdds: teamAOdds, teamBOdds: teamBOdds)
        let updated = MatchWithOdds(match: existing.match, odds: newOdds)
        matchDataMap[matchID] = updated

        if let index = allMatches.firstIndex(where: { $0.match.matchID == matchID }) {
            allMatches[index] = updated
        }

        oddsUpdated.send([matchID])
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
