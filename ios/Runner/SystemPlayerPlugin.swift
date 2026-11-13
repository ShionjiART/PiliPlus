import AVFoundation
import Flutter
import UIKit
import VideoToolbox

/// System player (AVPlayer) used instead of mpv for HDR / Dolby Vision videos
/// on iOS (and optionally for every on-demand video). mpv renders into an
/// 8-bit Flutter texture and its HDR output never matched AVPlayer, so these
/// videos are handed to AVPlayer and shown in a native platform view.
///
/// Dart side: `lib/plugin/pl_player/system_player.dart`.
final class SystemPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let channelName = "piliplus/system_player"
  static let viewType = "piliplus/system_player_view"

  private static weak var shared: SystemPlayerPlugin?
  private var sessions: [Int: SystemPlayerSession] = [:]
  private var nextId = 1
  private var eventSink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemPlayerPlugin()
    shared = instance
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "\(channelName)/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
    registrar.register(SystemPlayerViewFactory(), withId: viewType)
  }

  static func session(_ id: Int) -> SystemPlayerSession? { shared?.sessions[id] }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(_ id: Int, _ type: String, _ payload: [String: Any] = [:]) {
    var event = payload
    event["id"] = id
    event["type"] = type
    eventSink?(event)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["id"] as? Int ?? 0
    switch call.method {
    case "create":
      let newId = nextId
      nextId += 1
      sessions[newId] = SystemPlayerSession { [weak self] type, payload in
        self?.emit(newId, type, payload)
      }
      result(newId)
    case "load":
      guard let session = sessions[id] else { return result(nil) }
      session.load(args) { error in result(error) }
    case "play":
      sessions[id]?.play()
      result(nil)
    case "pause":
      sessions[id]?.player.pause()
      result(nil)
    case "seek":
      let ms = args["ms"] as? Int ?? 0
      sessions[id]?.seek(ms: ms) { result(nil) }
    case "setRate":
      sessions[id]?.setRate(Float(args["rate"] as? Double ?? 1))
      result(nil)
    case "setVolume":
      sessions[id]?.player.volume = Float(args["volume"] as? Double ?? 1)
      result(nil)
    case "info":
      result(sessions[id]?.info() ?? [:])
    case "dispose":
      sessions.removeValue(forKey: id)?.dispose()
      result(nil)
    case "supportsHardwareDecode":
      result(Self.supportsHardwareDecode(args["codec"] as? String ?? ""))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// AVPlayer has no software fallback for AV1 (or HEVC on very old devices).
  static func supportsHardwareDecode(_ codec: String) -> Bool {
    let type: CMVideoCodecType
    switch codec.prefix(4) {
    case "av01": type = kCMVideoCodecType_AV1
    case "hev1", "hvc1", "dvh1", "dvhe": type = kCMVideoCodecType_HEVC
    default: return true
    }
    return VTIsHardwareDecodeSupported(type)
  }
}

final class SystemPlayerSession: NSObject {
  let player = AVPlayer()
  private let emit: (String, [String: Any]) -> Void
  private var loader: SystemPlayerPlaylistLoader?
  private var timeObserver: Any?
  private var observations: [NSKeyValueObservation] = []
  private var itemObservers: [NSObjectProtocol] = []
  private var rate: Float = 1
  private var loadTask: Task<Void, Never>?
  private var lastPlaying: Bool?
  private var lastBuffering: Bool?
  // Shown in the playback info panel.
  private var videoInfo: SystemPlayerHLS.TrackInfo?
  private var audioInfo: SystemPlayerHLS.TrackInfo?
  private var videoURL: URL?
  private var audioURL: URL?
  private var frameRate: Double?

  init(emit: @escaping (String, [String: Any]) -> Void) {
    self.emit = emit
    super.init()
    player.automaticallyWaitsToMinimizeStalling = true
    player.appliesMediaSelectionCriteriaAutomatically = true
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 5), queue: .main
    ) { [weak self] time in
      self?.reportPosition(time)
    }
    observations.append(
      player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
        DispatchQueue.main.async { self?.reportStatus() }
      })
  }

  func load(_ args: [String: Any], completion: @escaping (String?) -> Void) {
    loadTask?.cancel()
    guard let video = Self.track(args["video"]) else { return completion("bad video") }
    let audio = Self.track(args["audio"])
    let headers = args["headers"] as? [String: String] ?? [:]
    let frameRate = args["frameRate"] as? Double
    let startMs = args["startMs"] as? Int ?? 0
    loadTask = Task { @MainActor in
      do {
        let (asset, loader, videoInfo, audioInfo) =
          try await SystemPlayerPlaylistLoader.makeAsset(
            video: video, audio: audio, frameRate: frameRate, headers: headers)
        if Task.isCancelled { return }
        self.loader = loader
        self.videoInfo = videoInfo
        self.audioInfo = audioInfo
        self.videoURL = video.url
        self.audioURL = audio?.url
        self.frameRate = frameRate
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        self.observe(item)
        self.player.replaceCurrentItem(with: item)
        if startMs > 0 {
          await self.player.seek(
            to: CMTime(value: CMTimeValue(startMs), timescale: 1000),
            toleranceBefore: .zero, toleranceAfter: .zero)
        }
        completion(nil)
      } catch {
        completion("\(error)")
      }
    }
  }

  private static func track(_ value: Any?) -> DashTrack? {
    guard let map = value as? [String: Any], let s = map["url"] as? String,
      let url = URL(string: s)
    else { return nil }
    return DashTrack(
      url: url, indexEnd: map["indexEnd"] as? Int ?? 65535,
      bandwidth: map["bandwidth"] as? Int ?? 1)
  }

  private func observe(_ item: AVPlayerItem) {
    for o in itemObservers { NotificationCenter.default.removeObserver(o) }
    itemObservers.removeAll()
    observations = observations.prefix(1).map { $0 }  // keep timeControlStatus
    observations.append(
      item.observe(\.status, options: [.new]) { [weak self] item, _ in
        DispatchQueue.main.async {
          guard let self else { return }
          if item.status == .readyToPlay {
            let d = item.duration
            if d.isNumeric { self.emit("duration", ["ms": Int(d.seconds * 1000)]) }
          } else if item.status == .failed {
            self.emit("error", ["message": item.error.map { "\($0)" } ?? "failed"])
          }
        }
      })
    observations.append(
      item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
        let s = item.presentationSize
        if s.width > 0 {
          DispatchQueue.main.async {
            self?.emit("size", ["width": Int(s.width), "height": Int(s.height)])
          }
        }
      })
    let center = NotificationCenter.default
    itemObservers.append(
      center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main)
      { [weak self] _ in self?.emit("completed", [:]) })
    itemObservers.append(
      center.addObserver(
        forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
      ) { [weak self] n in
        let error = n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
        self?.emit("error", ["message": error.map { "\($0)" } ?? "failed to play to end"])
      })
  }

  private func reportPosition(_ time: CMTime) {
    guard let item = player.currentItem, time.isNumeric else { return }
    var buffered = 0.0
    for value in item.loadedTimeRanges {
      let r = value.timeRangeValue
      if r.start <= time, time <= r.end { buffered = r.end.seconds }
    }
    emit("position", ["ms": Int(time.seconds * 1000), "bufferedMs": Int(buffered * 1000)])
  }

  private func reportStatus() {
    let playing = player.timeControlStatus != .paused
    let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    if playing != lastPlaying {
      lastPlaying = playing
      emit("playing", ["value": playing])
    }
    if buffering != lastBuffering {
      lastBuffering = buffering
      emit("buffering", ["value": buffering])
    }
  }

  /// What the playback info panel shows while this player is in use.
  func info() -> [String: Any] {
    var m: [String: Any] = [
      "rate": Double(player.rate),
      "volume": Double(player.volume),
      "eligibleForHDR": AVPlayer.eligibleForHDRPlayback,
    ]
    if let v = videoInfo {
      m["videoCodecs"] = v.codecs
      m["supplementalCodecs"] = v.supplementalCodecs
      m["videoRange"] = v.videoRange ?? "SDR"
      m["codedWidth"] = v.width
      m["codedHeight"] = v.height
    }
    m["audioCodecs"] = audioInfo?.codecs
    m["videoUrl"] = videoURL?.absoluteString
    m["audioUrl"] = audioURL?.absoluteString
    m["frameRate"] = frameRate
    guard let item = player.currentItem else { return m }
    let size = item.presentationSize
    if size.width > 0 {
      m["width"] = Int(size.width)
      m["height"] = Int(size.height)
    }
    if let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .video }),
      track.currentVideoFrameRate > 0
    {
      m["currentFrameRate"] = Double(track.currentVideoFrameRate)
    }
    if let event = item.accessLog()?.events.last {
      m["indicatedBitrate"] = event.indicatedBitrate
      m["observedBitrate"] = event.observedBitrate
      m["droppedFrames"] = event.numberOfDroppedVideoFrames
    }
    return m
  }

  func play() {
    if let item = player.currentItem, item.currentTime() >= item.duration, item.duration.isNumeric {
      player.seek(to: .zero)
    }
    player.playImmediately(atRate: rate)
  }

  func setRate(_ rate: Float) {
    self.rate = rate
    if #available(iOS 16.0, *) { player.defaultRate = rate }
    if player.rate != 0 { player.rate = rate }
  }

  func seek(ms: Int, completion: @escaping () -> Void) {
    player.seek(
      to: CMTime(value: CMTimeValue(ms), timescale: 1000),
      toleranceBefore: CMTime(value: 1, timescale: 10), toleranceAfter: CMTime(value: 1, timescale: 10)
    ) { _ in DispatchQueue.main.async(execute: completion) }
  }

  func dispose() {
    loadTask?.cancel()
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    for o in itemObservers { NotificationCenter.default.removeObserver(o) }
    itemObservers.removeAll()
    observations.removeAll()
    player.pause()
    player.replaceCurrentItem(with: nil)
    loader = nil
  }
}

// MARK: - Platform view

final class SystemPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let id = (args as? [String: Any])?["id"] as? Int ?? 0
    return SystemPlayerPlatformView(sessionId: id)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class SystemPlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class SystemPlayerPlatformView: NSObject, FlutterPlatformView {
  private let content = SystemPlayerLayerView()
  private var observers: [NSObjectProtocol] = []

  init(sessionId: Int) {
    super.init()
    content.backgroundColor = .black
    content.isUserInteractionEnabled = false
    // Flutter sizes this view to the video's aspect ratio (FittedBox).
    content.playerLayer.videoGravity = .resize
    let player = SystemPlayerPlugin.session(sessionId)?.player
    content.playerLayer.player = player
    // A player attached to a layer is paused when the app goes to the
    // background; detach it so "continue playing in background" keeps audio.
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.content.playerLayer.player = nil })
    observers.append(
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.content.playerLayer.player = player })
  }

  deinit {
    for o in observers { NotificationCenter.default.removeObserver(o) }
  }

  func view() -> UIView { content }
}
