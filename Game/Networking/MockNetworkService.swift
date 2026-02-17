import Foundation
import Combine

final class MockNetworkService: NetworkService {

    private let matches: [Match]
    private let odds: [MatchOdds]

    init() {
        let generated = Self.generateMockData()
        self.matches = generated.matches
        self.odds = generated.odds
    }

    // MARK: - NetworkService

    func get<T: Decodable>(path: String) -> AnyPublisher<T, Error> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data: Data
            switch path {
            case "/matches":
                data = try encoder.encode(matches)
            case "/odds":
                data = try encoder.encode(odds)
            default:
                return Fail(error: NetworkError.invalidPath)
                    .eraseToAnyPublisher()
            }

            let decoded = try decoder.decode(T.self, from: data)
            return Just(decoded)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: NetworkError.decodingFailed)
                .eraseToAnyPublisher()
        }
    }

    // MARK: - Mock Data Generation

    private static let teamNames = [
        "Eagles", "Tigers", "Lions", "Bears", "Wolves",
        "Hawks", "Panthers", "Sharks", "Dragons", "Cobras",
        "Falcons", "Stallions", "Thunder", "Lightning", "Blaze",
        "Vipers", "Raptors", "Knights", "Warriors", "Titans",
        "Phoenix", "Hurricanes", "Bulldogs", "Cougars", "Mustangs",
        "Ravens", "Scorpions", "Jaguars", "Hornets", "Spartans"
    ]

    private static func generateMockData() -> (matches: [Match], odds: [MatchOdds]) {
        var matches: [Match] = []
        var odds: [MatchOdds] = []
        let now = Date()

        for i in 0..<100 {
            let matchID = 1001 + i

            let teamAIndex = Int.random(in: 0..<teamNames.count)
            var teamBIndex = Int.random(in: 0..<teamNames.count)
            while teamBIndex == teamAIndex {
                teamBIndex = Int.random(in: 0..<teamNames.count)
            }

            // Random gap from now: 30 minutes to 7 days
            let gapSeconds = Int.random(in: 1_800...604_800)
            let startTime = now.addingTimeInterval(TimeInterval(gapSeconds))

            matches.append(Match(
                matchID: matchID,
                teamA: teamNames[teamAIndex],
                teamB: teamNames[teamBIndex],
                startTime: startTime
            ))

            // Odds between 1.10 and 5.00, rounded to 2 decimal places
            let teamAOdds = (Double.random(in: 1.10...5.00) * 100).rounded() / 100
            let teamBOdds = (Double.random(in: 1.10...5.00) * 100).rounded() / 100

            odds.append(MatchOdds(
                matchID: matchID,
                teamAOdds: teamAOdds,
                teamBOdds: teamBOdds
            ))
        }

        return (matches, odds)
    }
}
