import Foundation

struct ImageAttachment: Identifiable {
    let id: UUID
    let data: Data
    let fileExtension: String

    init(id: UUID = UUID(), data: Data, fileExtension: String = "jpg") {
        self.id = id
        self.data = data
        self.fileExtension = fileExtension
    }
}
