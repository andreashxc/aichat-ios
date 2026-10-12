import Foundation
import SwiftData

@Model
final class LocalModelDescriptor: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var filename: String
    var fileSize: Int
    var sha256: String?
    var sourceURL: URL?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        filename: String,
        fileSize: Int,
        sha256: String? = nil,
        sourceURL: URL? = nil,
        addedAt: Date = .init()
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.fileSize = fileSize
        self.sha256 = sha256
        self.sourceURL = sourceURL
        self.addedAt = addedAt
    }
}
