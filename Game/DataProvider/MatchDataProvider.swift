import Foundation
import Combine

protocol MatchDataProviding {
    var oddsStream: AnyPublisher<[MatchOdds], Never> { get }
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

    init(networkService: NetworkService, webSocketProvider: WebSocketProviding, storage: MatchStoring = MatchStorage()) {
        self.networkService = networkService
        self.webSocketProvider = webSocketProvider
        self.storage = storage
    }

    func saveToStorage(_ matches: [MatchWithOdds]) {
        storage.save(matches)
    }

    func connectOddsStream(matchIDs: [Int]) {
        webSocketProvider.connect(matchIDs: matchIDs)
    }

    func disconnectOddsStream() {
        webSocketProvider.disconnect()
    }

    func fetchMatchesWithOdds(reset: Bool) -> AnyPublisher<[MatchWithOdds], Error> {
        if reset {
            networkService.reset()
            storage.clear()
        }

        if !reset, let cached = storage.load() {
            return Just(cached)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        let matchesPublisher: AnyPublisher<[Match], Error> = networkService.get(path: "/matches")
        let oddsPublisher: AnyPublisher<[MatchOdds], Error> = networkService.get(path: "/odds")

        return Publishers.Zip(
            matchesPublisher.retry(5),
            oddsPublisher.retry(5)
        )
        .map { matches, odds in
            let oddsMap = Dictionary(uniqueKeysWithValues: odds.map { ($0.matchID, $0) })
            return matches
                .compactMap { match in
                    guard let matchOdds = oddsMap[match.matchID] else { return nil }
                    return MatchWithOdds(match: match, odds: matchOdds)
                }
                .sorted { $0.match.startTime < $1.match.startTime }
        }
        .eraseToAnyPublisher()
    }
}
