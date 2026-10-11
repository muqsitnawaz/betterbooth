import AVFoundation
import CoreLocation

/// H.264/AAC MP4 writer. Frame queue only.
final class Recorder {
    private let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var lastVideo = CMTime.negativeInfinity
    private var lastAudio = CMTime.negativeInfinity
    var failure: String? { writer.error?.localizedDescription }

    init(url: URL, size: CGSize, frameRate: FrameRate, audio: Bool, location: CLLocation?) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        if let location {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierLocation
            item.value = location.iso6709 as NSString
            writer.metadata = [item]
        }
        // About 6 bits per pixel per second at 30 fps: 12 Mbit/s for 1080p, 50 for 4K.
        let bitrate = Double(size.width * size.height) * 6 * frameRate.value / 30
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(bitrate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate.value,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(videoInput) else { throw CamError.message("The video track was refused") }
        writer.add(videoInput)
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CamError.message("The audio track was refused") }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        guard writer.startWriting() else { throw writer.error ?? CamError.message("The writer didn't start") }
    }

    /// Timestamps must rise; the writer fails the whole file on one that doesn't.
    func append(video frame: CVPixelBuffer, at time: CMTime) {
        guard time > lastVideo, writer.status == .writing else { return }
        lastVideo = time
        if startTime == nil {
            writer.startSession(atSourceTime: time)
            startTime = time
        }
        if videoInput.isReadyForMoreMediaData { adaptor.append(frame, withPresentationTime: time) }
    }

    func append(audio sample: CMSampleBuffer) {
        guard let startTime, let audioInput, audioInput.isReadyForMoreMediaData,
              writer.status == .writing else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        guard time >= startTime, time > lastAudio else { return }
        lastAudio = time
        audioInput.append(sample)
    }

    func finish(_ completion: @escaping (URL?) -> Void) {
        guard startTime != nil else {
            writer.cancelWriting()
            return completion(nil)
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [writer, url] in
            completion(writer.status == .completed ? url : nil)
        }
    }
}
