import Foundation
import Combine

final class MockWebSocketProvider: WebSocketProviding {

    var oddsStream: AnyPublisher<[MatchOdds], Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<[MatchOdds], Never>()
    private var matchIDs: [Int] = []
    private var timer: Timer?
    private var secondTimer: Timer?
    private var sentThisSecond = 0

    func connect(matchIDs: [Int]) {
        self.matchIDs = matchIDs
        cancelTimers()

        // Reset counter every second
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sentThisSecond = 0
        }

        scheduleNextBroadcast()
    }

    func disconnect() {
        cancelTimers()
        matchIDs = []
    }

    private func scheduleNextBroadcast() {
        let delay = Double.random(in: 0.01...0.1)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.broadcast()
        }
    }

    private func broadcast() {
        guard let matchID = matchIDs.randomElement(), sentThisSecond < 10 else {
            scheduleNextBroadcast()
            return
        }

        let update = MatchOdds(
            matchID: matchID,
            teamAOdds: (Double.random(in: 0.4...5.00) * 100).rounded() / 100,
            teamBOdds: (Double.random(in: 0.4...5.00) * 100).rounded() / 100
        )

        sentThisSecond += 1
        subject.send([update])
        scheduleNextBroadcast()
    }

    private func cancelTimers() {
        timer?.invalidate()
        timer = nil
        secondTimer?.invalidate()
        secondTimer = nil
        sentThisSecond = 0
    }
}
