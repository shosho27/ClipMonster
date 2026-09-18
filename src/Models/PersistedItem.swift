import Foundation

struct PersistedItem: Codable {
    let id: UUID
    let type: String
    let content: String
    let timestamp: Date
    var ocrText: String?
    var imageHash: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
}

