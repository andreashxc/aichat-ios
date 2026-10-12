import Foundation

struct AudioAttachment: Identifiable {
    let id: UUID
    let data: Data
    let fileExtension: String
    let fileName: String
    let mimeType: String
    let localPath: String?

    init(
        id: UUID = UUID(),
        data: Data,
        fileExtension: String,
        fileName: String,
        mimeType: String,
        localPath: String? = nil
    ) {
        self.id = id
        self.data = data
        self.fileExtension = fileExtension
        self.fileName = fileName
        self.mimeType = mimeType
        self.localPath = localPath
    }
}
