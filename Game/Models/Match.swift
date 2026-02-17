import Foundation

struct Match: Codable, Identifiable {
    let matchID: Int
    let teamA: String
    let teamB: String
    let startTime: Date

    var id: Int { matchID }
}
