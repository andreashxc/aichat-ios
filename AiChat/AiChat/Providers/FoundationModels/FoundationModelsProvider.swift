import Foundation

enum FoundationModelsAvailabilityStatus: Equatable {
    case available
    case unavailable(String)
}

@MainActor
protocol FoundationModelsProviding {
    var id: ProviderID { get }
    var displayName: String { get }
    func availabilityStatus() -> FoundationModelsAvailabilityStatus
    func generate(request: ChatRequest) async throws -> String
}

@MainActor
final class FoundationModelsProvider {
    private let impl: FoundationModelsProviding

    init() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            impl = FoundationModelsProviderLive()
        } else {
            impl = FoundationModelsProviderStub(reason: "Foundation Models require iOS 26.0 or later.")
        }
        #else
        impl = FoundationModelsProviderStub(reason: "Foundation Models are not available on this OS version.")
        #endif
    }

    init(impl: FoundationModelsProviding) {
        self.impl = impl
    }

    var id: ProviderID { impl.id }
    var displayName: String { impl.displayName }

    func availabilityStatus() -> FoundationModelsAvailabilityStatus {
        impl.availabilityStatus()
    }

    func generate(request: ChatRequest) async throws -> String {
        try await impl.generate(request: request)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@MainActor
final class FoundationModelsProviderLive: FoundationModelsProviding {
    var id: ProviderID { .foundationModels }
    var displayName: String { "Apple On-device (Foundation Models)" }

    private let model: SystemLanguageModel

    init(model: SystemLanguageModel) {
        self.model = model
    }

    convenience init() {
        self.init(model: .default)
    }

    func availabilityStatus() -> FoundationModelsAvailabilityStatus {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(String(describing: reason))
        @unknown default:
            return .unavailable("Unknown availability state.")
        }
    }

    func generate(request: ChatRequest) async throws -> String {
        try Task.checkCancellation()

        switch availabilityStatus() {
        case .available:
            break
        case .unavailable(let reason):
            throw AppError.featureUnavailable(reason)
        }

        let prompt = FoundationPromptBuilder.buildPrompt(
            context: request.contextMessages,
            userMessage: request.userMessageText,
            targetMessage: request.targetMessageText,
            systemPrompt: request.systemPrompt
        )

        // Create a new session for each request to ensure chat isolation
        // This prevents context bleeding between different conversations
        let session = LanguageModelSession(
            model: model,
            instructions: prompt.systemInstructions
        )

        let response = try await session.respond(to: prompt.body)
        try Task.checkCancellation()
        return response.content
    }
}
#endif

@MainActor
final class FoundationModelsProviderStub: FoundationModelsProviding {
    var id: ProviderID { .foundationModels }
    var displayName: String { "Apple On-device (Foundation Models)" }
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func availabilityStatus() -> FoundationModelsAvailabilityStatus {
        .unavailable(reason)
    }

    func generate(request: ChatRequest) async throws -> String {
        throw AppError.featureUnavailable(reason)
    }
}
