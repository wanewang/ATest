import Foundation
import Combine

protocol MatchDataProviding {
    var oddsStream: AnyPublisher<[MatchOdds], Never> { get }
    func fetchMatchesFromStorage() -> AnyPublisher<[MatchWithOdds]?, Never>
    func fetchMatchesWithOdds(reset: Bool) -> AnyPublisher<[MatchWithOdds], Error>
    func connectOddsStream(matchIDs: [Int])
    func disconnectOddsStream()
    func saveToStorage(_ matches: [MatchWithOdds])
}

extension MatchDataProviding {
    func fetchMatchesWithOdds() -> AnyPublisher<[MatchWithOdds], Error> {
        fetchMatchesWithOdds(reset: false)
    }
}

final class MatchDataProvider: MatchDataProviding {

    var oddsStream: AnyPublisher<[MatchOdds], Never> {
        webSocketProvider.oddsStream
    }

    private let networkService: NetworkService
    private let webSocketProvider: WebSocketProviding
    private let storage: MatchStoring
    private let storageQueue = DispatchQueue(label: "io.wane.Game.MatchDataProvider.storage", qos: .utility)

    init(networkService: NetworkService, webSocketProvider: WebSocketProviding, storage: MatchStoring = MatchStorage()) {
        self.networkService = networkService
        self.webSocketProvider = webSocketProvider
        self.storage = storage
    }

    func saveToStorage(_ matches: [MatchWithOdds]) {
        storageQueue.async { [storage] in
            storage.save(matches)
        }
    }

    func connectOddsStream(matchIDs: [Int]) {
        webSocketProvider.connect(matchIDs: matchIDs)
    }

    func disconnectOddsStream() {
        webSocketProvider.disconnect()
    }

    func fetchMatchesFromStorage() -> AnyPublisher<[MatchWithOdds]?, Never> {
        Deferred { [storageQueue, storage, networkService] in
            Future<[MatchWithOdds]?, Never> { promise in
                storageQueue.async {
                    guard let cached = storage.load() else {
                        promise(.success(nil))
                        return
                    }
                    let now = Date()
                    let valid = cached.filter { $0.match.startTime > now }
                    guard !valid.isEmpty else {
                        storage.clear()
                        promise(.success(nil))
                        return
                    }

                    // Seed mock network with cached matches + new data to pad to 100+
                    let existingMatches = valid.map(\.match)
                    networkService.generateAdditionalData(
                        excluding: existingMatches,
                        targetTotal: max(100, existingMatches.count)
                    )

                    promise(.success(valid))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func fetchMatchesWithOdds(reset: Bool) -> AnyPublisher<[MatchWithOdds], Error> {
        if reset {
            networkService.reset()
            storageQueue.async { [storage] in storage.clear() }
        }

        return fetchFromNetwork()
    }

    private func fetchFromNetwork() -> AnyPublisher<[MatchWithOdds], Error> {
        let matchesPublisher: AnyPublisher<[Match], Error> = networkService.get(path: "/matches")
        let oddsPublisher: AnyPublisher<[MatchOdds], Error> = networkService.get(path: "/odds")

        return Publishers.Zip(
            matchesPublisher.retry(5),
            oddsPublisher.retry(5)
        )
        .map { matches, odds in
            let oddsMap = self.oddsMapByMatchID(from: odds)
            return self.merge(matches: matches, with: oddsMap)
        }
        .eraseToAnyPublisher()
    }

    private func oddsMapByMatchID(from odds: [MatchOdds]) -> [Int: MatchOdds] {
        odds.reduce(into: [:]) { partialResult, item in
            partialResult[item.matchID] = item
        }
    }

    private func refresh(matches: [Match], with oddsMap: [Int: MatchOdds]) -> [MatchWithOdds] {
        matches
            .compactMap { match in
                guard let matchOdds = oddsMap[match.matchID] else { return nil }
                return MatchWithOdds(match: match, odds: matchOdds)
            }
    }

    private func merge(matches: [Match], with oddsMap: [Int: MatchOdds]) -> [MatchWithOdds] {
        refresh(matches: matches, with: oddsMap)
            .sorted { $0.match.startTime < $1.match.startTime }
    }
}
