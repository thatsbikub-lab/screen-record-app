import AVFoundation
import Flutter
import Photos
import ReplayKit

public class CaptureNestRecorderPlugin: NSObject, FlutterPlugin {
  private let recorder = RPScreenRecorder.shared()
  private let queue = DispatchQueue(label: "com.thatsbikublab.capturenest.writer")
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var audioInput: AVAssetWriterInput?
  private var outputURL: URL?
  private var hasStartedWriter = false
  private var isPaused = false
  private var useMicrophone = false
  private var useDeviceAudio = false
  private var pendingStop: FlutterResult?
  private var activeExport: AVAssetExportSession?
  // Paused or backgrounded time is cut out of the file by shifting later timestamps back.
  private var isSuspended = false
  private var awaitingResume = false
  private var timeOffset = CMTime.zero
  private var lastVideoTime = CMTime.invalid
  private var lastAudioTime = CMTime.invalid

  override init() {
    super.init()
    let center = NotificationCenter.default
    // iOS stops the hardware encoder in the background, which fails the writer with
    // "Operation Interrupted". Stop appending while inactive so the file stays valid.
    center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
      guard let self else { return }
      self.queue.async { self.isSuspended = true }
    }
    center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
      guard let self else { return }
      self.queue.async { self.isSuspended = false }
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.thatsbikublab.capturenest/recorder", binaryMessenger: registrar.messenger())
    let instance = CaptureNestRecorderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard let options = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_options", message: "Capture options are required.", details: nil))
        return
      }
      start(options: options, result: result)
    case "stop": stop(result: result)
    case "pause":
      guard writer != nil else {
        result(FlutterError(code: "not_recording", message: "There is no active capture.", details: nil))
        return
      }
      queue.async { self.isPaused = true }
      result(nil)
    case "resume":
      guard writer != nil else {
        result(FlutterError(code: "not_recording", message: "There is no active capture.", details: nil))
        return
      }
      queue.async { self.isPaused = false }
      result(nil)
    case "trim": trim(arguments: call.arguments, result: result)
    case "saveToGallery": saveToGallery(arguments: call.arguments, result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start(options: [String: Any], result: @escaping FlutterResult) {
    guard !recorder.isRecording else {
      result(FlutterError(code: "already_recording", message: "A capture is already in progress.", details: nil))
      return
    }
    useMicrophone = options["microphone"] as? Bool ?? false
    useDeviceAudio = options["deviceAudio"] as? Bool ?? false
    recorder.isMicrophoneEnabled = useMicrophone
    recorder.isCameraEnabled = options["frontCamera"] as? Bool ?? false
    let folder = recordingsDirectory()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let url = folder.appendingPathComponent("CaptureNest_\(formatter.string(from: Date())).mp4")
    try? FileManager.default.removeItem(at: url)
    do {
      writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
      outputURL = url
      videoInput = nil
      audioInput = nil
      hasStartedWriter = false
      isPaused = false
      awaitingResume = false
      timeOffset = .zero
      lastVideoTime = .invalid
      lastAudioTime = .invalid
    } catch {
      result(FlutterError(code: "writer_failed", message: error.localizedDescription, details: nil))
      return
    }

    recorder.startCapture(handler: { [weak self] sampleBuffer, sampleType, error in
      guard let self else { return }
      // Mid-capture errors end the capture; stop() saves whatever was already written.
      if error != nil { return }
      self.queue.async { self.append(sampleBuffer: sampleBuffer, type: sampleType) }
    }, completionHandler: { error in
      DispatchQueue.main.async {
        if let error {
          self.resetWriter(deleteOutput: true)
          result(FlutterError(code: "capture_denied", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    })
  }

  private func append(sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
    guard CMSampleBufferDataIsReady(sampleBuffer), let writer, writer.status != .failed else { return }
    if isPaused || isSuspended {
      if hasStartedWriter { awaitingResume = true }
      return
    }
    if awaitingResume {
      // Resume on a video frame so the gap is measured against the last written frame.
      guard type == .video else { return }
      let now = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      if lastVideoTime.isValid {
        timeOffset = now - lastVideoTime - CMTime(value: 1, timescale: 30)
      }
      awaitingResume = false
    }
    if type == .video && !hasStartedWriter {
      guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
      let dimensions = CMVideoFormatDescriptionGetDimensions(format)
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(dimensions.width),
        AVVideoHeightKey: Int(dimensions.height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
      ])
      input.expectsMediaDataInRealTime = true
      guard writer.canAdd(input) else { return }
      writer.add(input)
      videoInput = input
      let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000,
      ])
      audio.expectsMediaDataInRealTime = true
      if writer.canAdd(audio) {
        writer.add(audio)
        audioInput = audio
      }
      guard writer.startWriting() else { return }
      writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
      hasStartedWriter = true
    }
    guard hasStartedWriter, let buffer = retimed(sampleBuffer) else { return }
    let time = CMSampleBufferGetPresentationTimeStamp(buffer)
    if type == .video, let videoInput, videoInput.isReadyForMoreMediaData {
      if lastVideoTime.isValid && time <= lastVideoTime { return }
      if videoInput.append(buffer) { lastVideoTime = time }
    } else if (type == .audioMic && useMicrophone) || (type == .audioApp && !useMicrophone && useDeviceAudio),
              let audioInput, audioInput.isReadyForMoreMediaData {
      if lastAudioTime.isValid && time <= lastAudioTime { return }
      if audioInput.append(buffer) { lastAudioTime = time }
    }
  }

  private func retimed(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
    guard timeOffset != .zero else { return buffer }
    var count: CMItemCount = 0
    CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
    guard count > 0 else { return nil }
    var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
    CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
    for index in timing.indices {
      timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - timeOffset
      if timing[index].decodeTimeStamp.isValid {
        timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - timeOffset
      }
    }
    var copy: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: buffer,
      sampleTimingEntryCount: count,
      sampleTimingArray: &timing,
      sampleBufferOut: &copy
    )
    return copy
  }

  private func stop(result: @escaping FlutterResult) {
    guard pendingStop == nil else {
      result(FlutterError(code: "already_stopping", message: "The recording is already being saved.", details: nil))
      return
    }
    guard recorder.isRecording || writer != nil else {
      result(FlutterError(code: "not_recording", message: "There is no active capture.", details: nil))
      return
    }
    pendingStop = result
    guard recorder.isRecording else {
      // ReplayKit ended the capture by itself; still save whatever was written.
      finalizeWriter()
      return
    }
    recorder.stopCapture { [weak self] _ in
      // A stop error usually means the capture had already ended; the file decides success.
      self?.finalizeWriter()
    }
  }

  private func finalizeWriter() {
    queue.async {
      guard let writer = self.writer, self.hasStartedWriter, writer.status == .writing, let output = self.outputURL else {
        let message = self.writer?.status == .failed
          ? "The recording was interrupted and could not be saved."
          : "No video frames were captured."
        DispatchQueue.main.async {
          self.finishStop(NSError(domain: "CaptureNest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        return
      }
      self.videoInput?.markAsFinished()
      self.audioInput?.markAsFinished()
      writer.finishWriting {
        DispatchQueue.main.async { self.finishStop(writer.error, output: output) }
      }
    }
  }

  private func finishStop(_ error: Error?, output: URL? = nil) {
    let callback = pendingStop
    pendingStop = nil
    if let error {
      resetWriter(deleteOutput: true)
      callback?(FlutterError(code: "capture_failed", message: error.localizedDescription, details: nil))
      return
    }
    let path = output?.path ?? outputURL?.path
    resetWriter(deleteOutput: false)
    callback?(path)
  }

  private func trim(arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
          let inputPath = values["inputPath"] as? String,
          let from = values["fromMs"] as? NSNumber,
          let to = values["toMs"] as? NSNumber,
          to.int64Value > from.int64Value else {
      result(FlutterError(code: "bad_trim", message: "Choose a valid start and end time.", details: nil))
      return
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let output = recordingsDirectory().appendingPathComponent("CaptureNest_trim_\(formatter.string(from: Date())).mp4")
    try? FileManager.default.removeItem(at: output)
    let asset = AVURLAsset(url: URL(fileURLWithPath: inputPath))
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      result(FlutterError(code: "trim_failed", message: "This video cannot be exported.", details: nil))
      return
    }
    activeExport = export
    export.outputURL = output
    export.outputFileType = .mp4
    export.timeRange = CMTimeRange(
      start: CMTime(value: from.int64Value, timescale: 1000),
      duration: CMTime(value: to.int64Value - from.int64Value, timescale: 1000)
    )
    export.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        self?.activeExport = nil
        if export.status == .completed { result(output.path) }
        else { result(FlutterError(code: "trim_failed", message: export.error?.localizedDescription ?? "The video could not be exported.", details: nil)) }
      }
    }
  }

  private func saveToGallery(arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any], let path = values["path"] as? String else {
      result(FlutterError(code: "bad_path", message: "A video path is required.", details: nil))
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        result(FlutterError(code: "gallery_denied", message: "Photo Library access was not granted.", details: nil))
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: path))
      }) { success, error in
        DispatchQueue.main.async {
          success ? result(nil) : result(FlutterError(code: "gallery_failed", message: error?.localizedDescription ?? "The video could not be saved.", details: nil))
        }
      }
    }
  }

  private func recordingsDirectory() -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let folder = documents.appendingPathComponent("CaptureNest", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func resetWriter(deleteOutput: Bool) {
    let output = outputURL
    writer = nil
    videoInput = nil
    audioInput = nil
    outputURL = nil
    hasStartedWriter = false
    isPaused = false
    awaitingResume = false
    timeOffset = .zero
    lastVideoTime = .invalid
    lastAudioTime = .invalid
    if deleteOutput, let output { try? FileManager.default.removeItem(at: output) }
  }
}


