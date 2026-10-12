import Foundation

actor ParagraphDeliveryPipeline {
    private var isCancelled = false

    func split(_ text: String) -> [String] {
        ParagraphDeliveryPipeline.splitText(text)
    }

    func cancel() {
        isCancelled = true
    }

    func shouldContinue() -> Bool {
        !isCancelled
    }

    static func splitText(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        var currentIsBullet = false

        func flush() {
            let joined = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                paragraphs.append(joined)
            }
            current.removeAll()
            currentIsBullet = false
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
                continue
            }

            let isBullet = line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("•")
            if !current.isEmpty, currentIsBullet, !isBullet {
                flush()
            }
            currentIsBullet = isBullet
            current.append(line)
        }

        flush()
        return paragraphs
    }
}
