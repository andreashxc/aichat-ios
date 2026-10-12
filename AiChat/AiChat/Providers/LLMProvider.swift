import Foundation

protocol LLMProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    func generate(request: ChatRequest) async throws -> String
    func supportsModels() -> Bool
    func availableModels() async -> [ModelInfo]
}
