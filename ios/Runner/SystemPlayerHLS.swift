import AVFoundation
import Foundation

/// One DASH representation (bilibili "m4s" file) to expose to AVPlayer.
struct DashTrack {
  let url: URL
  /// End offset (inclusive) of `segment_base.index_range`, i.e. where the
  /// `sidx` box ends. The file head up to here holds ftyp + moov + sidx.
  let indexEnd: Int
  let bandwidth: Int
}

enum SystemPlayerHLSError: Error {
  case badResponse(Int)
  case noSidx
}

/// Turns bilibili DASH files into fMP4 HLS playlists.
///
/// AVPlayer can open a progressive fragmented MP4 directly, but it walks every
/// `moof` before playback starts: a 20-minute 4K HDR file (3.3 GB, 242
/// fragments) never started within 30 s. With a playlist built from the file's
/// own `sidx`, AVPlayer only fetches the init section and the first fragment
/// and starts in about a second. Segments stay on the CDN as byte ranges.
enum SystemPlayerHLS {
  struct Media {
    let initLength: Int
    let segments: [(offset: Int, length: Int, duration: Double)]
    let info: TrackInfo
  }

  /// What the HLS master playlist must declare. AVPlayer refuses 4K/60 HDR
  /// variants unless CODECS, RESOLUTION, FRAME-RATE and VIDEO-RANGE are all
  /// present, and bilibili's DASH `codecs` string does not always match the
  /// real sample entry (DV 8.4 files are `hvc1` + `dvvC`), so read them from
  /// the init section instead.
  struct TrackInfo {
    var codecs: String?
    var supplementalCodecs: String?
    var videoRange: String?  // SDR / PQ / HLG
    var width = 0
    var height = 0
    /// Transfer characteristics in the HEVC SPS (16 PQ, 18 HLG), if any.
    var spsTransfer: Int?
  }

  /// Fetches `[0, track.indexEnd]` and parses ftyp/moov/sidx.
  static func load(_ track: DashTrack, headers: [String: String]) async throws -> Media {
    var request = URLRequest(url: track.url)
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    request.setValue("bytes=0-\(track.indexEnd)", forHTTPHeaderField: "Range")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 206 || status == 200 else { throw SystemPlayerHLSError.badResponse(status) }
    return try parse([UInt8](data))
  }

  static func parse(_ b: [UInt8]) throws -> Media {
    func u32(_ i: Int) -> Int {
      Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
    func u64(_ i: Int) -> Int { u32(i) << 32 | u32(i + 4) }
    var i = 0
    var initEnd = 0
    var info = TrackInfo()
    while i + 8 <= b.count {
      var size = u32(i)
      let type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
      if size == 1 { size = u64(i + 8) }
      if size < 8 { break }
      if type == "ftyp" || type == "moov" { initEnd = i + size }
      if type == "moov", i + size <= b.count { info = trackInfo(b, i + 8, i + size) }
      if type == "sidx" {
        let version = b[i + 8]
        var off = i + 12
        let timescale = Double(u32(off + 4))
        off += 8
        let firstOffset: Int
        if version == 0 {
          firstOffset = u32(off + 4)
          off += 8
        } else {
          firstOffset = u64(off + 8)
          off += 16
        }
        let count = Int(b[off + 2]) << 8 | Int(b[off + 3])
        off += 4
        var pos = i + size + firstOffset
        var segments: [(Int, Int, Double)] = []
        for _ in 0..<count {
          let length = u32(off) & 0x7fff_ffff
          let duration = Double(u32(off + 4)) / timescale
          segments.append((pos, length, duration))
          pos += length
          off += 12
        }
        return Media(initLength: initEnd, segments: segments, info: info)
      }
      i += size
    }
    throw SystemPlayerHLSError.noSidx
  }

  // MARK: - Init section parsing (codec strings for the master playlist)

  private static func trackInfo(_ b: [UInt8], _ start: Int, _ end: Int) -> TrackInfo {
    var info = TrackInfo()
    var colrRange: String?
    var dolbyRange: String?
    func u16(_ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    func u32(_ i: Int) -> Int { u16(i) << 16 | u16(i + 2) }
    func hex(_ v: Int) -> String { String(v, radix: 16, uppercase: true) }

    func walk(_ from: Int, _ to: Int) {
      var i = from
      while i + 8 <= to {
        let size = u32(i)
        guard size >= 8, i + size <= to else { return }
        let type = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
        let body = i + 8
        switch type {
        case "moov", "trak", "mdia", "minf", "stbl":
          walk(body, i + size)
        case "stsd":
          walk(body + 8, i + size)  // version/flags + entry_count
        case "hvc1", "hev1", "dvh1", "dvhe", "avc1", "avc3", "av01":
          info.width = u16(body + 24)
          info.height = u16(body + 26)
          info.codecs = type  // refined by the config boxes below
          walk(body + 78, i + size)
        case "mp4a", "ec-3", "ac-3", "fLaC", "Opus":
          info.codecs = type == "mp4a" ? "mp4a.40.2" : type
          walk(body + 28, i + size)
        case "hvcC":
          let p = body + 1
          let space = ["", "A", "B", "C"][Int(b[p]) >> 6]
          let tier = (b[p] >> 5) & 1 == 1 ? "H" : "L"
          let profile = Int(b[p]) & 0x1f
          var compat = u32(p + 1)
          var reversed = 0
          for _ in 0..<32 {
            reversed = reversed << 1 | (compat & 1)
            compat >>= 1
          }
          var constraints = (0..<6).map { Int(b[p + 5 + $0]) }
          while constraints.last == 0 { constraints.removeLast() }
          let level = Int(b[p + 11])
          let entry = info.codecs == "hev1" || info.codecs == "dvhe" ? "hev1" : "hvc1"
          var s = "\(entry).\(space)\(profile).\(hex(reversed)).\(tier)\(level)"
          for c in constraints { s += "." + hex(c) }
          // A dvh1/dvhe entry (profile 5) keeps its Dolby Vision string.
          if info.codecs?.hasPrefix("dv") != true { info.codecs = s }
          info.spsTransfer = SystemPlayerHEVC.transfer(hvcC: b, body: body, end: i + size)
        case "avcC":
          info.codecs = String(format: "avc1.%02X%02X%02X", b[body + 1], b[body + 2], b[body + 3])
        case "av1C":
          let profile = Int(b[body + 1]) >> 5
          let level = Int(b[body + 1]) & 0x1f
          let tier = (b[body + 2] >> 7) & 1 == 1 ? "H" : "M"
          let depth = (b[body + 2] >> 5) & 1 == 1 ? 12 : ((b[body + 2] >> 6) & 1 == 1 ? 10 : 8)
          info.codecs = String(format: "av01.%d.%02d%@.%02d", profile, level, tier, depth)
        case "dvcC", "dvvC", "dvwC":
          let profile = Int(b[body + 2]) >> 1
          let level = (Int(b[body + 2]) & 1) << 5 | Int(b[body + 3]) >> 3
          let compat = Int(b[body + 4]) >> 4
          let dv = String(format: "dvh1.%02d.%02d", profile, level)
          if info.codecs?.hasPrefix("dv") == true {
            info.codecs = dv  // profile 5: Dolby Vision only
            dolbyRange = "PQ"
          } else {
            // Profile 8.x: HEVC base layer, Dolby Vision as a supplement.
            let brand = [1: "db1p", 2: "db2g", 4: "db4h"][compat]
            info.supplementalCodecs = brand.map { "\(dv)/\($0)" } ?? dv
            // The base layer's range follows from the compatibility id;
            // bilibili's DV streams have no `colr` box to read it from.
            dolbyRange = [1: "PQ", 2: "SDR", 4: "HLG", 6: "PQ"][compat]
          }
        case "colr":
          if String(bytes: b[body..<(body + 4)], encoding: .ascii) == "nclx" {
            colrRange = range(transfer: u16(body + 6))
          }
        case "esds":
          // ES_Descriptor > DecoderConfigDescriptor > DecoderSpecificInfo
          var p = body + 4
          func descriptor(_ tag: UInt8) -> Bool {
            guard p < i + size, b[p] == tag else { return false }
            p += 1
            while p < i + size, b[p] & 0x80 != 0 { p += 1 }
            p += 1
            return true
          }
          if descriptor(0x03) {
            let flags = b[p + 2]
            p += 3
            if flags & 0x80 != 0 { p += 2 }
            if flags & 0x40 != 0 { p += 1 + Int(b[p]) }
            if flags & 0x20 != 0 { p += 2 }
            if descriptor(0x04) {
              let object = b[p]
              p += 13
              if object == 0x40, descriptor(0x05) {
                var aot = Int(b[p]) >> 3
                if aot == 31 { aot = 32 + ((Int(b[p]) & 7) << 3 | Int(b[p + 1]) >> 5) }
                info.codecs = "mp4a.40.\(aot)"
              } else if object == 0x6b || object == 0x69 {
                info.codecs = "mp4a.6B"
              }
            }
          }
        default:
          break
        }
        i += size
      }
    }
    walk(start, end)
    if info.width > 0 {
      // AVPlayer checks VIDEO-RANGE against the bitstream, so the SPS wins;
      // bilibili's DV and some HDR streams have no `colr` box.
      info.videoRange =
        info.spsTransfer.map(range(transfer:)) ?? colrRange ?? dolbyRange ?? "SDR"
    }
    return info
  }

  private static func range(transfer: Int) -> String {
    switch transfer {
    case 16: return "PQ"
    case 18: return "HLG"
    default: return "SDR"
    }
  }

  static func mediaPlaylist(_ media: Media, url: URL) -> String {
    let target = Int((media.segments.map(\.duration).max() ?? 6).rounded(.up))
    var lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:7",
      "#EXT-X-PLAYLIST-TYPE:VOD",
      "#EXT-X-INDEPENDENT-SEGMENTS",
      "#EXT-X-TARGETDURATION:\(target)",
      "#EXT-X-MAP:URI=\"\(url.absoluteString)\",BYTERANGE=\"\(media.initLength)@0\"",
    ]
    for s in media.segments {
      lines.append(String(format: "#EXTINF:%.6f,", s.duration))
      lines.append("#EXT-X-BYTERANGE:\(s.length)@\(s.offset)")
      lines.append(url.absoluteString)
    }
    lines.append("#EXT-X-ENDLIST")
    return lines.joined(separator: "\n") + "\n"
  }

  /// Highest bitrate of any segment, in bits per second. HLS wants BANDWIDTH
  /// to be the peak; bilibili's `bandwidth` is the average.
  static func peakBitrate(_ media: Media) -> Int {
    media.segments.reduce(0) { peak, s in
      s.duration > 0 ? max(peak, Int(Double(s.length * 8) / s.duration)) : peak
    }
  }

  static func masterPlaylist(
    video: DashTrack, videoMedia: Media, audio: DashTrack?, audioMedia: Media?,
    frameRate: Double?
  ) -> String {
    let videoInfo = videoMedia.info
    let audioInfo = audioMedia?.info
    var lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-INDEPENDENT-SEGMENTS"]
    let average = video.bandwidth + (audio?.bandwidth ?? 0)
    let peak = peakBitrate(videoMedia) + (audioMedia.map(peakBitrate) ?? 0)
    var attrs = ["BANDWIDTH=\(max(peak, average, 1))"]
    if average > 0 { attrs.append("AVERAGE-BANDWIDTH=\(average)") }
    let codecs = [videoInfo.codecs, audioInfo?.codecs].compactMap { $0 }
    if !codecs.isEmpty { attrs.append("CODECS=\"\(codecs.joined(separator: ","))\"") }
    if let s = videoInfo.supplementalCodecs { attrs.append("SUPPLEMENTAL-CODECS=\"\(s)\"") }
    if videoInfo.width > 0 { attrs.append("RESOLUTION=\(videoInfo.width)x\(videoInfo.height)") }
    if let frameRate, frameRate > 0 { attrs.append(String(format: "FRAME-RATE=%.3f", frameRate)) }
    attrs.append("VIDEO-RANGE=\(videoInfo.videoRange ?? "SDR")")
    if audioInfo != nil {
      lines.append(
        "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aud\",NAME=\"audio\",DEFAULT=YES,AUTOSELECT=YES,URI=\"audio.m3u8\"")
      attrs.append("AUDIO=\"aud\"")
    }
    lines.append("#EXT-X-STREAM-INF:" + attrs.joined(separator: ","))
    lines.append("video.m3u8")
    return lines.joined(separator: "\n") + "\n"
  }
}

/// Serves the generated playlists to AVPlayer under a private URL scheme.
/// Segment URIs inside are plain https URLs, which AVPlayer fetches itself
/// (with the asset's HTTP header option applied).
final class SystemPlayerPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate {
  static let scheme = "piliplus-hls"
  let playlists: [String: Data]

  init(playlists: [String: String]) {
    self.playlists = playlists.mapValues { Data($0.utf8) }
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let url = loadingRequest.request.url, url.scheme == Self.scheme,
      let data = playlists[url.lastPathComponent]
    else { return false }
    loadingRequest.contentInformationRequest?.contentType = "public.m3u-playlist"
    loadingRequest.contentInformationRequest?.contentLength = Int64(data.count)
    loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
    if let dataRequest = loadingRequest.dataRequest {
      let start = Int(dataRequest.requestedOffset)
      let end = dataRequest.requestsAllDataToEndOfResource
        ? data.count : min(data.count, start + dataRequest.requestedLength)
      dataRequest.respond(with: data.subdata(in: start..<end))
    }
    loadingRequest.finishLoading()
    return true
  }

  /// Builds all playlists for a video (+ optional audio) and returns an asset.
  static func makeAsset(
    video: DashTrack, audio: DashTrack?, frameRate: Double?, headers: [String: String]
  ) async throws -> (
    AVURLAsset, SystemPlayerPlaylistLoader, video: SystemPlayerHLS.TrackInfo,
    audio: SystemPlayerHLS.TrackInfo?
  ) {
    async let v = SystemPlayerHLS.load(video, headers: headers)
    var playlists: [String: String] = [:]
    var audioMedia: SystemPlayerHLS.Media?
    if let audio {
      let a = try await SystemPlayerHLS.load(audio, headers: headers)
      audioMedia = a
      playlists["audio.m3u8"] = SystemPlayerHLS.mediaPlaylist(a, url: audio.url)
    }
    let videoMedia = try await v
    playlists["video.m3u8"] = SystemPlayerHLS.mediaPlaylist(videoMedia, url: video.url)
    playlists["master.m3u8"] = SystemPlayerHLS.masterPlaylist(
      video: video, videoMedia: videoMedia, audio: audio, audioMedia: audioMedia,
      frameRate: frameRate)
    let loader = SystemPlayerPlaylistLoader(playlists: playlists)
    let asset = AVURLAsset(
      url: URL(string: "\(scheme)://playlist/master.m3u8")!,
      options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    asset.resourceLoader.setDelegate(loader, queue: .main)
    return (asset, loader, videoMedia.info, audioMedia?.info)
  }
}
