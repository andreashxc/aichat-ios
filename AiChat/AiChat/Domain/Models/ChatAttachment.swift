import Foundation

struct ChatAttachment: Codable, Hashable, Identifiable {
    let id: UUID
    let data: Data
    let mimeType: String

    init(id: UUID = UUID(), data: Data, mimeType: String) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
    }
}
