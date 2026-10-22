import AVFoundation
import Photos
import ReplayKit

/// System-wide recording started from Control Center or CaptureNest's broadcast picker.
/// The finished video is saved straight to Photos, so no shared container is needed.
class SampleHandler: RPBroadcastSampleHandler {
  private let queue = DispatchQueue(label: "com.thatsbikublab.capturenest.broadcast.writer")
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var appAudioInput: AVAssetWriterInput?
  private var micAudioInput: AVAssetWriterInput?
  private var outputURL: URL?
  private var sessionStarted = false
  private var finished = false

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    guard status == .authorized || status == .limited else {
      finishBroadcastWithError(NSError(domain: "CaptureNest", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Open CaptureNest and allow Photos access so recordings can be saved.",
      ]))
      return
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("CaptureNest_\(formatter.string(from: Date())).mp4")
    try? FileManager.default.removeItem(at: url)
    do {
      let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      queue.sync {
        self.writer = writer
        self.outputURL = url
      }
    } catch {
      finishBroadcastWithError(error)
    }
  }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    queue.sync { append(sampleBuffer, type: sampleBufferType) }
  }

  override func broadcastFinished() {
    let written = DispatchSemaphore(value: 0)
    var output: URL?
    var writerToCheck: AVAssetWriter?
    queue.sync {
      finished = true
      guard let writer, sessionStarted, writer.status == .writing else { return }
      videoInput?.markAsFinished()
      appAudioInput?.markAsFinished()
      micAudioInput?.markAsFinished()
      output = outputURL
      writerToCheck = writer
      writer.finishWriting { written.signal() }
    }
    guard let output, let writerToCheck else { return }
    // broadcastFinished must not return before the file is saved, or iOS ends the extension.
    _ = written.wait(timeout: .now() + 20)
    if writerToCheck.status == .completed {
      try? PHPhotoLibrary.shared().performChangesAndWait {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: output)
      }
    }
    try? FileManager.default.removeItem(at: output)
  }

  private func append(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
    guard !finished, let writer, CMSampleBufferDataIsReady(sampleBuffer) else { return }
    if sessionStarted && writer.status != .writing { return }
    switch type {
    case .video:
      if !sessionStarted {
        guard startWriter(writer, firstFrame: sampleBuffer) else { return }
      }
      if let videoInput, videoInput.isReadyForMoreMediaData { videoInput.append(sampleBuffer) }
    case .audioApp:
      if sessionStarted, let appAudioInput, appAudioInput.isReadyForMoreMediaData { appAudioInput.append(sampleBuffer) }
    case .audioMic:
      if sessionStarted, let micAudioInput, micAudioInput.isReadyForMoreMediaData { micAudioInput.append(sampleBuffer) }
    @unknown default:
      break
    }
  }

  private func startWriter(_ writer: AVAssetWriter, firstFrame: CMSampleBuffer) -> Bool {
    guard let format = CMSampleBufferGetFormatDescription(firstFrame) else { return false }
    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(dimensions.width),
      AVVideoHeightKey: Int(dimensions.height),
      AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
    ])
    video.expectsMediaDataInRealTime = true
    guard writer.canAdd(video) else { return false }
    writer.add(video)
    videoInput = video
    // Device sound and microphone go to separate tracks; players mix them on playback.
    appAudioInput = addAudioInput(to: writer)
    micAudioInput = addAudioInput(to: writer)
    guard writer.startWriting() else { return false }
    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(firstFrame))
    sessionStarted = true
    return true
  }

  private func addAudioInput(to writer: AVAssetWriter) -> AVAssetWriterInput? {
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 2,
      AVEncoderBitRateKey: 128_000,
    ])
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else { return nil }
    writer.add(input)
    return input
  }
}
