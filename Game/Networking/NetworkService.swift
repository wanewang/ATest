import Foundation
import Combine

enum NetworkError: Error, LocalizedError {
    case invalidPath
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "Invalid request path"
        case .requestFailed: return "Network request failed"
        case .decodingFailed: return "Failed to decode response"
        }
    }
}

protocol NetworkService {
    func get<T: Decodable>(path: String) -> AnyPublisher<T, Error>
    func reset()
    func generateAdditionalData(excluding existingMatches: [Match], targetTotal: Int)
}
