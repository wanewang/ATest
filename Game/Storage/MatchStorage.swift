import Foundation

protocol MatchStoring {
    func save(_ matches: [MatchWithOdds])
    func load() -> [MatchWithOdds]?
    func clear()
}

final class MatchStorage: MatchStoring {

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileName: String = "cached_matches.json") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.fileURL = caches.appendingPathComponent(fileName)

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ matches: [MatchWithOdds]) {
        do {
            let data = try encoder.encode(matches)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[MatchStorage] save failed: \(error)")
        }
    }

    func load() -> [MatchWithOdds]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode([MatchWithOdds].self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
