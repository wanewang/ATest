import Foundation
import Combine

final class MatchListViewModel: ObservableObject {

    @Published private(set) var displayedMatchIDs: [Int] = []

    private(set) var matchDataMap: [Int: MatchWithOdds] = [:]

    /// Emits matchIDs whose odds changed — subscribers reconfigure only those cells.
    let oddsUpdated = PassthroughSubject<[Int], Never>()

    private var allMatches: [MatchWithOdds] = []
    private var currentPage = 0
    private var isLoading = false
    private var hasMorePages = true
    private let pageSize = 40

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

    private func fetchAll() {
        isLoading = true

        dataProvider.fetchMatchesWithOdds()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                },
                receiveValue: { [weak self] matches in
                    guard let self else { return }
                    self.allMatches = matches
                    for m in matches {
                        self.matchDataMap[m.match.matchID] = m
                    }
                    self.appendNextPage()
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
