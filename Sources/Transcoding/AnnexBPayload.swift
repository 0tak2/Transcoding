import Foundation

public struct AnnexBPayload: Sendable, Codable {
    public let annexBData: Data
    public let presentationTimestamp: TimeInterval

    public init(annexBData: Data, presentationTimestamp: TimeInterval) {
        self.annexBData = annexBData
        self.presentationTimestamp = presentationTimestamp
    }
}
