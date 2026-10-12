import Foundation

enum AppError: Error, LocalizedError {
    case invalidRequest
    case notImplemented
    case featureUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The request could not be created."
        case .notImplemented:
            return "This feature is not implemented yet."
        case .featureUnavailable(let reason):
            return reason
        }
    }
}
