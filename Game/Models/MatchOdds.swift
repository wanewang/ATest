import Foundation

struct MatchOdds: Codable, Identifiable {
    let matchID: Int
    let teamAOdds: Double
    let teamBOdds: Double

    var id: Int { matchID }
}
