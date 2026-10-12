import Foundation

enum LocalRuntimePhase: String, Sendable {
    case idle
    case loading
    case loaded
    case generating
    case error

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
        case .loaded:
            return "Loaded"
        case .generating:
            return "Generating"
        case .error:
            return "Error"
        }
    }
}

struct LocalRuntimeStatus: Equatable, Sendable {
    var phase: LocalRuntimePhase
    var currentModelId: String?
    var backend: EngineType?
    var tokensPerSecond: Double?
    var message: String?

    static let idle = LocalRuntimeStatus(
        phase: .idle,
        currentModelId: nil,
        backend: nil,
        tokensPerSecond: nil,
        message: nil
    )

    var summary: String {
        var parts = [phase.displayName]
        if let currentModelId {
            parts.append(currentModelId)
        }
        if let backend {
            parts.append(backend.displayName)
        }
        if let tokensPerSecond {
            parts.append("\(String(format: "%.1f", tokensPerSecond)) tok/s")
        }
        if let message, !message.isEmpty {
            parts.append(message)
        }
        return parts.joined(separator: " • ")
    }
}
