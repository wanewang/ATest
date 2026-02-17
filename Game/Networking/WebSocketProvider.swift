import Foundation
import Combine

protocol WebSocketProviding {
    var oddsStream: AnyPublisher<[MatchOdds], Never> { get }
    func connect(matchIDs: [Int])
    func disconnect()
}
