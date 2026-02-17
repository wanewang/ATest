import Foundation
import Combine

protocol MatchDataProviding {
    var oddsStream: AnyPublisher<[MatchOdds], Never> { get }
    func fetchMatchesWithOdds(reset: Bool) -> AnyPublisher<[MatchWithOdds], Error>
    func connectOddsStream(matchIDs: [Int])
    func disconnectOddsStream()
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

    init(networkService: NetworkService, webSocketProvider: WebSocketProviding) {
        self.networkService = networkService
        self.webSocketProvider = webSocketProvider
    }

    deinit {
        print("cache here?")
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
