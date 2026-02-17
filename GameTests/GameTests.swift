import XCTest
import Combine
@testable import Game

final class MatchListViewModelTests: XCTestCase {

    @MainActor
    func testLoadNextPageLoadsFirstAndSecondPages() {
        let provider = MockMatchDataProvider()
        provider.fetchHandler = { _ in
            Just(Self.makeMatches(count: 45))
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        let viewModel = MatchListViewModel(dataProvider: provider)
        viewModel.loadNextPage()

        waitUntil("first page should be loaded") {
            viewModel.displayedMatchIDs.count == 40
        }
        XCTAssertEqual(provider.connectCalls.count, 1)
        XCTAssertEqual(provider.connectCalls.first?.count, 45)

        viewModel.loadNextPage()
        waitUntil("second page should be loaded") {
            viewModel.displayedMatchIDs.count == 45
        }
    }

    @MainActor
    func testOddsStreamUpdatesMatchDataAndEmitsChangedIDs() {
        let provider = MockMatchDataProvider()
        let initial = Self.makeMatches(count: 2)
        provider.fetchHandler = { _ in
            Just(initial)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        let viewModel = MatchListViewModel(dataProvider: provider)
        var emittedIDs: [Int] = []
        var cancellables = Set<AnyCancellable>()
        viewModel.oddsUpdated
            .sink { emittedIDs.append(contentsOf: $0) }
            .store(in: &cancellables)

        viewModel.loadNextPage()
        waitUntil("initial data should be loaded") {
            viewModel.displayedMatchIDs.count == 2
        }

        let targetID = initial[0].match.matchID
        provider.oddsSubject.send([
            MatchOdds(matchID: targetID, teamAOdds: 3.21, teamBOdds: 1.89)
        ])

        waitUntil("odds update should be emitted") {
            emittedIDs.contains(targetID)
        }
        XCTAssertEqual(viewModel.match(for: targetID)?.odds.teamAOdds, 3.21)
    }

    @MainActor
    func testRetryCancelsPreviousFetchResult() {
        let provider = MockMatchDataProvider()
        let retryFetch = PassthroughSubject<[MatchWithOdds], Error>()
        let freshData = Self.makeMatches(count: 1, idStart: 2_000)

        provider.fetchHandler = { _ in
            retryFetch.eraseToAnyPublisher()
        }

        let viewModel = MatchListViewModel(dataProvider: provider)
        viewModel.loadNextPage()
        viewModel.retry()

        // Retry cancels the initial storage subscription before it fires,
        // so only the retry's fetchMatchesWithOdds(reset: true) is called.
        waitUntil("retry fetch should be registered") {
            provider.fetchCalls.count == 1
        }

        retryFetch.send(freshData)
        retryFetch.send(completion: .finished)

        waitUntil("retry fetch should win") {
            viewModel.displayedMatchIDs == [freshData[0].match.matchID]
        }
        XCTAssertEqual(provider.fetchCalls, [true])
    }

    @MainActor
    func testFetchFromStorageReturnsNilFallsBackToNetwork() {
        let provider = MockMatchDataProvider()
        provider.storageResult = nil

        let networkData = Self.makeMatches(count: 3)
        provider.fetchHandler = { _ in
            Just(networkData)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        let viewModel = MatchListViewModel(dataProvider: provider)
        viewModel.loadNextPage()

        waitUntil("network data should be loaded") {
            viewModel.displayedMatchIDs.count == 3
        }
        XCTAssertEqual(provider.fetchCalls, [false])
    }

    @MainActor
    func testFetchFromStorageReturnsCachedThenRefreshesFromNetwork() {
        let provider = MockMatchDataProvider()
        let cachedData = Self.makeMatches(count: 2, idStart: 500)
        provider.storageResult = cachedData

        let networkSubject = PassthroughSubject<[MatchWithOdds], Error>()
        let networkData = Self.makeMatches(count: 5, idStart: 500)
        provider.fetchHandler = { _ in
            networkSubject.eraseToAnyPublisher()
        }

        let viewModel = MatchListViewModel(dataProvider: provider)
        viewModel.loadNextPage()

        // Cached data should appear first
        waitUntil("cached data should be displayed") {
            viewModel.displayedMatchIDs.count == 2
        }

        // Send network data after cached is displayed
        networkSubject.send(networkData)
        networkSubject.send(completion: .finished)

        // Network refresh replaces with fresh data
        waitUntil("network refresh should replace data") {
            viewModel.displayedMatchIDs.count == 5
        }
        XCTAssertEqual(provider.fetchCalls, [false])
    }

    // MARK: - Helpers

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1.0,
        condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail(description)
    }

    @MainActor
    private func waitForMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private static func makeMatches(count: Int, idStart: Int = 100) -> [MatchWithOdds] {
        let start = Date().addingTimeInterval(600)
        return (0..<count).map { offset in
            let id = idStart + offset
            let match = Match(
                matchID: id,
                teamA: "TeamA\(id)",
                teamB: "TeamB\(id)",
                startTime: start.addingTimeInterval(Double(offset) * 60)
            )
            let odds = MatchOdds(
                matchID: id,
                teamAOdds: 1.5 + Double(offset) * 0.01,
                teamBOdds: 2.5 + Double(offset) * 0.01
            )
            return MatchWithOdds(match: match, odds: odds)
        }
    }
}

private final class MockMatchDataProvider: MatchDataProviding {

    let oddsSubject = PassthroughSubject<[MatchOdds], Never>()
    var oddsStream: AnyPublisher<[MatchOdds], Never> {
        oddsSubject.eraseToAnyPublisher()
    }

    var fetchCalls: [Bool] = []
    var connectCalls: [[Int]] = []
    var disconnectCallCount = 0
    var savedSnapshots: [[MatchWithOdds]] = []
    var fetchHandler: ((Bool) -> AnyPublisher<[MatchWithOdds], Error>)?
    var storageResult: [MatchWithOdds]? = nil

    func fetchMatchesFromStorage() -> AnyPublisher<[MatchWithOdds]?, Never> {
        Just(storageResult).eraseToAnyPublisher()
    }

    func fetchMatchesWithOdds(reset: Bool) -> AnyPublisher<[MatchWithOdds], Error> {
        fetchCalls.append(reset)
        if let fetchHandler {
            return fetchHandler(reset)
        }
        return Just([])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func connectOddsStream(matchIDs: [Int]) {
        connectCalls.append(matchIDs)
    }

    func disconnectOddsStream() {
        disconnectCallCount += 1
    }

    func saveToStorage(_ matches: [MatchWithOdds]) {
        savedSnapshots.append(matches)
    }
}
