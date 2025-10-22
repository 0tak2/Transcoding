import CoreMedia
import Foundation
import OSLog

// MARK: - VideoDecoderAnnexBAdaptor

public final class VideoDecoderAnnexBAdaptor {
    /// Sender의 첫 프레임 기준점
    private var firstSenderHostTime: TimeInterval?
    
    /// Receiver가 첫 프레임을 받은 시점 (Receiver의 HostTime 기준)
    private var firstReceiverHostTime: CMTime?

    // MARK: Lifecycle

    public init(
        videoDecoder: VideoDecoder,
        codec: Codec
    ) {
        self.videoDecoder = videoDecoder
        self.codec = codec
    }

    // MARK: Public

    public func decode(_ data: Data) {
        switch codec {
        case .h264:
            decodeH264(data)
        case .hevc:
            decodeHEVC(data)
        }
    }

    public func decode(_ payload: AnnexBPayload) {
        let receiverHostTimePTS = self.convertPayloadToReceiverHostTime(payload)

        switch codec {
        case .h264:
            decodeH264(payload.annexBData, pts: receiverHostTimePTS)
        case .hevc:
            decodeHEVC(payload.annexBData, pts: receiverHostTimePTS)
        }
    }

    // MARK: Internal

    static let logger = Logger(subsystem: "Transcoding", category: "VideoDecoderAnnexBAdaptor")

    let videoDecoder: VideoDecoder
    let codec: Codec
    var formatDescription: CMVideoFormatDescription?

    var vps: Data?
    var sps: Data?
    var pps: Data?

    func decodeH264(_ data: Data, pts: CMTime? = nil) {
        for nalu in data.split(separator: H264NALU.startCode).map({ H264NALU(data: Data($0)) }) {
            if nalu.isSPS {
                sps = nalu.data
            } else if nalu.isPPS {
                pps = nalu.data
            } else if nalu.isPFrame || nalu.isIFrame {
                if nalu.isIFrame, let sps, let pps {
                    do {
                        let formatDescription = try CMVideoFormatDescription(h264ParameterSets: [sps, pps])
                        videoDecoder.setFormatDescription(formatDescription)
                        self.formatDescription = formatDescription
                    } catch {
                        Self.logger.error("Failed to create format description with error: \(error, privacy: .public)")
                    }
                }
                decodeAVCCFrame(nalu.avcc, pts: pts)
            }
        }
    }

    func decodeHEVC(_ data: Data, pts: CMTime? = nil) {
        for nalu in data.split(separator: HEVCNALU.startCode).map({ HEVCNALU(data: Data($0)) }) {
            if nalu.isVPS {
                vps = nalu.data
            } else if nalu.isSPS {
                sps = nalu.data
            } else if nalu.isPPS {
                pps = nalu.data
            } else if nalu.isPFrame || nalu.isIFrame {
                if nalu.isIFrame, let vps, let sps, let pps {
                    do {
                        let formatDescription = try CMVideoFormatDescription(hevcParameterSets: [vps, sps, pps])
                        videoDecoder.setFormatDescription(formatDescription)
                        self.formatDescription = formatDescription
                    } catch {
                        Self.logger.error("Failed to create format description with error: \(error, privacy: .public)")
                    }
                }
                decodeAVCCFrame(nalu.avcc, pts: pts)
            }
        }
    }

    func decodeAVCCFrame(_ data: Data, pts: CMTime? = nil) {
        guard let formatDescription else {
            Self.logger.warning("No format description; need sync frame")
            return
        }

        let timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts ?? .invalid,
            decodeTimeStamp: pts ?? .invalid
        )

        var data = data
        data.withUnsafeMutableBytes { pointer in
            do {
                let dataBuffer = try CMBlockBuffer(buffer: pointer, allocator: kCFAllocatorNull)
                let sampleBuffer = try CMSampleBuffer(
                    dataBuffer: dataBuffer,
                    formatDescription: formatDescription,
                    numSamples: 1,
                    sampleTimings: [timingInfo],
                    sampleSizes: []
                )
                videoDecoder.decode(sampleBuffer)
            } catch {
                Self.logger.error("Failed to create sample buffer with error: \(error, privacy: .public)")
            }
        }
    }

    /// Payload의 상대 시간을 Receiver의 Host Time으로 변환한다.
    private func convertPayloadToReceiverHostTime(_ payload: AnnexBPayload) -> CMTime {
        
        // 1. 첫 프레임 수신 시, Receiver의 기준점을 설정
        if firstSenderHostTime == nil || firstReceiverHostTime == nil {
            firstSenderHostTime = payload.firstFrameTimestamp
            firstReceiverHostTime = CMClockGetTime(CMClockGetHostTimeClock())
            
            Self.logger.debug("Decoder synchronized clocks. First Sender TS: \(payload.firstFrameTimestamp)")
            // 첫 프레임은 계산된 HostTime (지금)을 반환
            return firstReceiverHostTime!
        }
        
        // 2. 두 번째 프레임부터는 오프셋 기준으로 계산
        
        // (미디어 시간 경과) = (현재 프레임 PTS) - (첫 프레임 PTS)
        let mediaDurationSeconds = payload.presentationTimestamp - payload.firstFrameTimestamp
        
        // (Receiver의 HostTime 기준 PTS 계산)
        // targetHostTime = (Receiver의 첫 시간) + (미디어 시간 경과)
        let targetHostTime = CMTimeAdd(firstReceiverHostTime!, mediaDurationSeconds.cmTime)
        
        return targetHostTime
    }
}

// MARK: VideoDecoderAnnexBAdaptor.Codec

public extension VideoDecoderAnnexBAdaptor {
    enum Codec {
        case h264
        case hevc
    }
}

// MARK: Util
private extension TimeInterval {
    var cmTime: CMTime {
        let scale = CMTimeScale(NSEC_PER_SEC)
        let rt = CMTime(value: CMTimeValue(self * Double(scale)), timescale: scale)
        return rt
    }
}
