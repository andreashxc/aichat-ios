import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let modelContainer: ModelContainer
    let conversationStore: ConversationStore
    let contextBudgeter: ContextBudgeter
    let foundationModelsProvider: FoundationModelsProvider
    let localProvider: any LocalProviding

    @Published var providerConfig: ProviderConfig
    @Published var activeConversation: Conversation?
    @Published var persistenceError: PersistenceErrorState?

    init(
        modelContainer: ModelContainer,
        providerConfig: ProviderConfig = ProviderConfig(),
        foundationModelsProvider: FoundationModelsProvider? = nil,
        localProvider: (any LocalProviding)? = nil
    ) {
        let normalizedConfig = providerConfig.normalized()
        self.modelContainer = modelContainer
        self.conversationStore = ConversationStore(modelContext: modelContainer.mainContext)
        self.contextBudgeter = ContextBudgeter()
        self.foundationModelsProvider = foundationModelsProvider ?? FoundationModelsProvider()
        self.localProvider = localProvider ?? LocalProvider()
        self.providerConfig = normalizedConfig
        self.activeConversation = nil
        self.persistenceError = nil

        self.conversationStore.persistenceErrorHandler = { [weak self] operation, error in
            self?.reportPersistenceError(error, operation: operation)
        }
        self.activeConversation = conversationStore.bootstrapConversation(defaultProvider: normalizedConfig.activeProvider)
    }

    func ensureConversation() -> Conversation {
        if let activeConversation {
            return activeConversation
        }
        let conversation = conversationStore.bootstrapConversation(defaultProvider: providerConfig.activeProvider.resolvedSupportedProvider)
        activeConversation = conversation
        return conversation
    }

    func reportPersistenceError(_ error: Error, operation: String) {
        let state = PersistenceErrorState(operation: operation, message: error.localizedDescription)
        persistenceError = state
        Logger.shared.error("Persistence error during \(operation): \(error.localizedDescription)")
    }

    func clearPersistenceError() {
        persistenceError = nil
    }
}

struct PersistenceErrorState: Identifiable, Equatable {
    let id = UUID()
    let operation: String
    let message: String
    let occurredAt: Date

    init(operation: String, message: String, occurredAt: Date = Date()) {
        self.operation = operation
        self.message = message
        self.occurredAt = occurredAt
    }
}
