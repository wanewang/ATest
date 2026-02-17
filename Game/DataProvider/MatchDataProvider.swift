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
