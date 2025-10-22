import Foundation

public struct AnnexBPayload: Sendable, Codable {
    let annexBData: Data
    let presentationTimestamp: TimeInterval
}
