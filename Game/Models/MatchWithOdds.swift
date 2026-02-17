import Foundation

struct MatchWithOdds: Identifiable {
    let match: Match
    let odds: MatchOdds

    var id: Int { match.matchID }
}
