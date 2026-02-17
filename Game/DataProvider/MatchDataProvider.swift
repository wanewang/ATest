import Foundation
import Combine

protocol MatchDataProviding {
    func fetchMatchesWithOdds() -> AnyPublisher<[MatchWithOdds], Error>
}

final class MatchDataProvider: MatchDataProviding {

    private let networkService: NetworkService

    init(networkService: NetworkService) {
        self.networkService = networkService
    }

    func fetchMatchesWithOdds() -> AnyPublisher<[MatchWithOdds], Error> {
        let matchesPublisher: AnyPublisher<[Match], Error> = networkService
            .get(path: "/matches")
        let retriedMatches = matchesPublisher.retry(5).eraseToAnyPublisher()

        let oddsPublisher: AnyPublisher<[MatchOdds], Error> = networkService
            .get(path: "/odds")
        let retriedOdds = oddsPublisher.retry(5).eraseToAnyPublisher()

        return Publishers.Zip(retriedMatches, retriedOdds)
            .map { matches, odds in
                let oddsMap = Dictionary(uniqueKeysWithValues: odds.map { ($0.matchID, $0) })
                return matches.compactMap { match in
                    guard let matchOdds = oddsMap[match.matchID] else { return nil }
                    return MatchWithOdds(match: match, odds: matchOdds)
                }
            }
            .eraseToAnyPublisher()
    }
}
