import Foundation
import UIKit
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

    /// Emits matchIDs whose odds changed — subscribers reconfigure only those cells.
    let oddsUpdated = PassthroughSubject<[Int], Never>()

    // MARK: - Data queue–owned state

    private let dataQueue = DispatchQueue(label: "io.wane.Game.MatchListViewModel.data", qos: .userInitiated)
    private let dataQueueKey = DispatchSpecificKey<Void>()
    private var matchDataMap: [Int: MatchWithOdds] = [:]
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
    private var fetchCancellable: AnyCancellable?
    private var cacheTimer: Timer?

    init(dataProvider: MatchDataProviding) {
        self.dataProvider = dataProvider
        dataQueue.setSpecific(key: dataQueueKey, value: ())
        subscribeToOddsStream()
        observeAppLifecycle()
    }

    deinit {
        cacheTimer?.invalidate()
        fetchCancellable?.cancel()
        dataProvider.disconnectOddsStream()
    }

    // MARK: - Public (main thread)

    func loadNextPage() {
        guard !isLoading else { return }

        dataQueue.async { [weak self] in
            guard let self else { return }
            guard self.hasMorePages else { return }

            if self.allMatches.isEmpty {
                DispatchQueue.main.async {
                    self.fetchAll()
                }
            } else {
                let ids = self.computeNextPage()
                DispatchQueue.main.async {
                    guard let ids else { return }
                    self.displayedMatchIDs.append(contentsOf: ids)
                }
            }
        }
    }

    func retry() {
        dataQueue.async { [weak self] in
            guard let self else { return }
            self.allMatches = []
            self.matchDataMap = [:]
            self.currentPage = 0
            self.hasMorePages = true
        }
        fetchAll(reset: true)
    }

    /// Thread-safe read for cell configuration (called from main thread).
    func match(for id: Int) -> MatchWithOdds? {
        if DispatchQueue.getSpecific(key: dataQueueKey) != nil {
            return matchDataMap[id]
        }
        return dataQueue.sync { matchDataMap[id] }
    }

    // MARK: - App lifecycle & caching

    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.handleDidEnterBackground() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .dropFirst()
            .sink { [weak self] _ in self?.handleDidBecomeActive() }
            .store(in: &cancellables)
    }

    private func handleDidEnterBackground() {
        cacheTimer?.invalidate()
        cacheTimer = nil
        saveToStorage()
        dataProvider.disconnectOddsStream()
    }

    private func handleDidBecomeActive() {
        dataQueue.async { [weak self] in
            guard let self, !self.allMatches.isEmpty else { return }
            let matchIDs = self.allMatches.map(\.match.matchID)
            DispatchQueue.main.async {
                self.dataProvider.connectOddsStream(matchIDs: matchIDs)
                self.startCacheTimer()
            }
        }
    }

    private func startCacheTimer() {
        cacheTimer?.invalidate()
        cacheTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.saveToStorage()
        }
    }

    private func saveToStorage() {
        dataQueue.async { [weak self] in
            guard let self, !self.allMatches.isEmpty else { return }
            self.dataProvider.saveToStorage(self.allMatches)
        }
    }

    // MARK: - Real-time odds

    private func subscribeToOddsStream() {
        dataProvider.oddsStream
            .receive(on: dataQueue)
            .compactMap { [weak self] batch -> [Int]? in
                self?.processOddsUpdates(batch)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changedIDs in
                self?.oddsUpdated.send(changedIDs)
            }
            .store(in: &cancellables)
    }

    /// Runs on `dataQueue`.
    private func processOddsUpdates(_ batch: [MatchOdds]) -> [Int]? {
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
        return changedIDs.isEmpty ? nil : changedIDs
    }

    // MARK: - Fetch

    private func fetchAll(reset: Bool = false) {
        loadState = .loading

        if reset {
            dataQueue.async { [weak self] in
                self?.fetchFromNetwork(reset: true)
            }
            return
        }

        // Try storage first, then background-refresh from network
        dataQueue.async { [weak self] in
            guard let self else { return }
            self.fetchCancellable?.cancel()
            self.fetchCancellable = self.dataProvider.fetchMatchesFromStorage()
                .receive(on: self.dataQueue)
                .sink { [weak self] cached in
                    guard let self else { return }
                    if let cached, !cached.isEmpty {
                        let pageIDs = self.applyMatches(cached)
                        DispatchQueue.main.async {
                            self.displayedMatchIDs = pageIDs
                            self.loadState = .loaded
                            self.connectAndStartTimer()
                        }
                        // Background refresh for fresh data
                        self.fetchFromNetwork(reset: false)
                    } else {
                        self.fetchFromNetwork(reset: false)
                    }
                }
        }
    }

    /// Runs on `dataQueue`.
    private func fetchFromNetwork(reset: Bool) {
        fetchCancellable?.cancel()
        fetchCancellable = dataProvider.fetchMatchesWithOdds(reset: reset)
            .receive(on: dataQueue)
            .map { [weak self] matches -> [Int] in
                self?.applyMatches(matches) ?? []
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let error) = completion {
                        self.loadState = .failed(error)
                    }
                },
                receiveValue: { [weak self] pageIDs in
                    guard let self else { return }
                    self.displayedMatchIDs = pageIDs
                    self.loadState = .loaded
                    self.connectAndStartTimer()
                }
            )
    }

    /// Runs on `dataQueue`. Replaces all data and returns first page IDs.
    @discardableResult
    private func applyMatches(_ matches: [MatchWithOdds]) -> [Int] {
        allMatches = matches
        matchDataMap = [:]
        currentPage = 0
        hasMorePages = true
        for m in matches {
            matchDataMap[m.match.matchID] = m
        }
        return computeNextPage() ?? []
    }

    private func connectAndStartTimer() {
        dataQueue.async { [weak self] in
            guard let self else { return }
            let matchIDs = self.allMatches.map(\.match.matchID)
            DispatchQueue.main.async {
                self.dataProvider.connectOddsStream(matchIDs: matchIDs)
                self.startCacheTimer()
            }
        }
    }

    /// Runs on `dataQueue`. Returns next page IDs or nil if no more pages.
    private func computeNextPage() -> [Int]? {
        let start = currentPage * pageSize
        guard start < allMatches.count else {
            hasMorePages = false
            return nil
        }
        let end = min(start + pageSize, allMatches.count)
        let ids = allMatches[start..<end].map(\.match.matchID)
        currentPage += 1
        if end >= allMatches.count {
            hasMorePages = false
        }
        return ids
    }
}
