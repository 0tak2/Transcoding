import Foundation

public struct AnnexBPayload: Sendable, Codable {
    public let annexBData: Data
    public let presentationTimestamp: TimeInterval
}
