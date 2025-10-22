import Foundation

public struct AnnexBPayload: Sendable, Codable {
    public let annexBData: Data
    public let firstFrameTimestamp: TimeInterval
    public let presentationTimestamp: TimeInterval

    public init(annexBData: Data, firstFrameTimestamp: TimeInterval, presentationTimestamp: TimeInterval) {
        self.annexBData = annexBData
        self.firstFrameTimestamp = firstFrameTimestamp
        self.presentationTimestamp = presentationTimestamp
    }
}
