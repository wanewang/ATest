import Foundation
import Combine

final class MockWebSocketProvider: WebSocketProviding {

    var oddsStream: AnyPublisher<[MatchOdds], Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<[MatchOdds], Never>()
    private var matchIDs: [Int] = []
    private var timer: Timer?

    func connect(matchIDs: [Int]) {
        self.matchIDs = matchIDs
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.broadcast()
        }
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
    }

    private func broadcast() {
        guard !matchIDs.isEmpty else { return }

        let count = Int.random(in: 1...min(10, matchIDs.count))
        let selected = matchIDs.shuffled().prefix(count)

        let updates = selected.map { id in
            MatchOdds(
                matchID: id,
                teamAOdds: (Double.random(in: 1.10...5.00) * 100).rounded() / 100,
                teamBOdds: (Double.random(in: 1.10...5.00) * 100).rounded() / 100
            )
        }

        subject.send(updates)
    }
}
