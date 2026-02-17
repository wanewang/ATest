import Foundation

struct MatchWithOdds: Codable, Identifiable {
    let match: Match
    let odds: MatchOdds

    var id: Int { match.matchID }
}
