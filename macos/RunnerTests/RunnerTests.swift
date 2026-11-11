import AVFoundation
import FlutterMacOS
import XCTest
import just_audio

final class RunnerTests: XCTestCase {
  func testAbsentConfigurationPreservesTimeDomain() throws {
    try assertAlgorithm(loadControl: nil, expected: .timeDomain)
  }

  func testTimeDomainReachesInitialAndLoopItems() throws {
    let configuration = LoadControl()
    configuration.useSpectralTimePitchAlgorithm = false
    try assertAlgorithm(loadControl: configuration, expected: .timeDomain)
  }

  func testSpectralReachesInitialAndLoopItems() throws {
    let configuration = LoadControl()
    configuration.useSpectralTimePitchAlgorithm = true
    try assertAlgorithm(loadControl: configuration, expected: .spectral)
  }

  private func assertAlgorithm(
    loadControl: LoadControl?, expected: AVAudioTimePitchAlgorithm
  ) throws {
    // Construction inspects real AVPlayerItem properties. No decoder or audio
    // device is used, and this fixture does not establish audible quality.
    let source = try XCTUnwrap(UriAudioSource(
      id: "speed-fixture",
      uri: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("crisper-speed-fixture.wav").absoluteString,
      loadControl: loadControl,
      headers: [:],
      options: ["darwinAssetOptions": ["preferPreciseDurationAndTiming": false]]
    ))
    let firstItem = try XCTUnwrap(source.playerItem)
    XCTAssertEqual(firstItem.audioTimePitchAlgorithm, expected)
    XCTAssertNil(source.playerItem2)
    source.preparePlayerItem2()
    let loopItem = try XCTUnwrap(source.playerItem2)
    XCTAssertEqual(loopItem.audioTimePitchAlgorithm, expected)
    source.flip()
    XCTAssertTrue(source.playerItem === loopItem)
    XCTAssertTrue(source.playerItem2 === firstItem)
    XCTAssertEqual(source.playerItem.audioTimePitchAlgorithm, expected)
  }

  func testPortableEngineNamesAndInvalidSelection() {
    for (name, identifier) in ["sonic": 0, "bungee": 1, "signalsmith": 2, "wsola": 3] {
      XCTAssertEqual(CrisperPortableAudioPlayer.engineIdentifier(for: name), identifier)
    }
    XCTAssertEqual(CrisperPortableAudioPlayer.engineIdentifier(for: "unknown"), -1)
  }

  func testPortableFileDecoderStreamsAllFourEngines() throws {
    let url = try makePortableFixture(frames: 48_000)
    defer { try? FileManager.default.removeItem(at: url) }
    for engine in 0...3 {
      for rate in [0.5, 1.0, 1.5, 3.0] {
        let stream = try XCTUnwrap(CrisperDspStream(
          url: url, engine: engine, rate: rate, clipStart: 0, clipEnd: -1, position: 0
        ))
        XCTAssertEqual(stream.durationMicroseconds, 1_000_000)
        XCTAssertEqual(stream.mediaPosition(outputFrames: 0), 0)
        var frames: Int64 = 0
        var peak: Float = 0
        while !stream.isEnded {
          let buffer = try XCTUnwrap(stream.read(frames: 127))
          XCTAssertLessThanOrEqual(buffer.frameLength, 127)
          let channels = try XCTUnwrap(buffer.floatChannelData)
          for index in 0..<Int(buffer.frameLength) {
            XCTAssertTrue(channels[0][index].isFinite)
            XCTAssertTrue(channels[1][index].isFinite)
            // Both channels of the file are identical; transport must preserve
            // the channel relationship through interleave/deinterleave.
            XCTAssertEqual(channels[0][index], channels[1][index], accuracy: 0.00001)
            peak = max(peak, abs(channels[0][index]))
          }
          frames += Int64(buffer.frameLength)
          XCTAssertLessThanOrEqual(frames, Int64((48_000 / rate).rounded()))
        }
        XCTAssertEqual(frames, Int64((48_000 / rate).rounded()))
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertEqual(stream.mediaPosition(outputFrames: frames), 1_000_000)
        XCTAssertEqual(try stream.read(frames: 127).frameLength, 0)
      }
    }
  }

  func testPortableSeekClipAndUnitySamples() throws {
    let url = try makePortableFixture(frames: 48_000)
    defer { try? FileManager.default.removeItem(at: url) }
    for engine in 0...3 {
      let stream = try XCTUnwrap(CrisperDspStream(
        url: url, engine: engine, rate: 1, clipStart: 250_000,
        clipEnd: 750_000, position: 125_000
      ))
      XCTAssertEqual(stream.durationMicroseconds, 500_000)
      XCTAssertEqual(stream.mediaPosition(outputFrames: 0), 125_000)
      let first = try XCTUnwrap(stream.read(frames: 11))
      let samples = try XCTUnwrap(first.floatChannelData)
      for index in 0..<11 {
        let expected = Float(0.25 * sin(2 * Double.pi * 440 * Double(18_000 + index) / 48_000))
        XCTAssertEqual(samples[0][index], expected, accuracy: 0.000001)
      }
      var frames = Int64(first.frameLength)
      while !stream.isEnded { frames += Int64(try stream.read(frames: 4096).frameLength) }
      XCTAssertEqual(frames, 18_000)
      XCTAssertEqual(stream.mediaPosition(outputFrames: frames), 500_000)
    }
  }

  func testPortableRejectsRemoteInputAndInvalidRate() throws {
    XCTAssertThrowsError(try CrisperDspStream(
      url: URL(string: "https://example.invalid/book.mp3")!, engine: 0,
      rate: 1, clipStart: 0, clipEnd: -1, position: 0
    ))
    let url = try makePortableFixture(frames: 64)
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertThrowsError(try CrisperDspStream(
      url: url, engine: 1, rate: 0, clipStart: 0, clipEnd: -1, position: 0
    ))
  }

  private func makePortableFixture(frames: AVAudioFrameCount) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("crisper-portable-\(UUID().uuidString).caf")
    let format = try XCTUnwrap(AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
    ))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channels = try XCTUnwrap(buffer.floatChannelData)
    for index in 0..<Int(frames) {
      let value = Float(0.25 * sin(2 * Double.pi * 440 * Double(index) / 48_000))
      channels[0][index] = value
      channels[1][index] = value
    }
    try file.write(from: buffer)
    return url
  }

  func testPortableNodeTransportSeekSpeedAndCompletion() throws {
    let url = try makePortableFixture(frames: 96_000)
    defer { try? FileManager.default.removeItem(at: url) }
    for engine in 0...3 {
      var events: [[AnyHashable: Any]] = []
      let player = CrisperPortableAudioPlayer(engine: engine, manualRendering: true) { events.append($0) }
      defer { player.dispose(false) }
      _ = try portableCommand(player, "load", [
        "audioSource": portablePlaylist([portableFile(url, id: "book")]),
        "initialPosition": 0, "initialIndex": 0,
      ])
      XCTAssertEqual(events.last?["updatePosition"] as? Int, 0, "Queued DSP output must not advance source time")
      _ = try portableCommand(player, "setSpeed", ["speed": 1.5])
      let firstPlay = expectation(description: "Pause resolves play")
      player.handleMethodCall(FlutterMethodCall(methodName: "play", arguments: [:])) { result in
        XCTAssertFalse(result is FlutterError)
        firstPlay.fulfill()
      }
      var peak: Float = 0
      for _ in 0..<3 {
        let output = try portableRender(player, frames: 4096)
        let channel = try XCTUnwrap(output.floatChannelData)[0]
        for frame in 0..<Int(output.frameLength) { peak = max(peak, abs(channel[frame])) }
      }
      XCTAssertGreaterThan(peak, 0.01, "The AVAudioEngine must render real processed PCM")
      _ = try portableCommand(player, "pause", [:])
      wait(for: [firstPlay], timeout: 2)
      let paused = try XCTUnwrap(events.last?["updatePosition"] as? Int)
      XCTAssertGreaterThan(paused, 250_000)
      XCTAssertLessThan(paused, 500_000)
      // Rejected offline rendering cannot consume paused source audio.
      XCTAssertThrowsError(try portableRender(player, frames: 4096))
      XCTAssertEqual(events.last?["updatePosition"] as? Int, paused)
      _ = try portableCommand(player, "seek", ["position": 500_000, "index": 0])
      XCTAssertEqual(events.last?["updatePosition"] as? Int, 500_000)
      _ = try portableCommand(player, "setSpeed", ["speed": 2.0])
      let ended = expectation(description: "Finite node drain resolves play")
      player.handleMethodCall(FlutterMethodCall(methodName: "play", arguments: [:])) { result in
        XCTAssertFalse(result is FlutterError)
        ended.fulfill()
      }
      for _ in 0..<128 {
        if events.last?["processingState"] as? Int == 4 { break }
        _ = try portableRender(player, frames: 4096)
      }
      wait(for: [ended], timeout: 3)
      XCTAssertEqual(events.last?["processingState"] as? Int, 4)
      XCTAssertEqual(events.last?["updatePosition"] as? Int, 2_000_000)
    }
  }

  func testPortableNodeSkipsEmptyTracksAndBoundsEmptyLoops() throws {
    let url = try makePortableFixture(frames: 4_800)
    defer { try? FileManager.default.removeItem(at: url) }
    let empty: (String) -> [String: Any] = { id in
      ["type": "clipping", "id": id, "start": 0, "end": 0,
       "child": self.portableFile(url, id: id + "-file")]
    }
    for loop in [0, 1, 2] {
      var events: [[AnyHashable: Any]] = []
      let player = CrisperPortableAudioPlayer(engine: 3, manualRendering: true) { events.append($0) }
      defer { player.dispose(false) }
      let children = loop == 0
        ? [empty("first"), portableFile(url, id: "audible"), empty("last")]
        : [empty("first"), empty("last")]
      _ = try portableCommand(player, "load", [
        "audioSource": portablePlaylist(children), "initialPosition": 0, "initialIndex": 0,
      ])
      _ = try portableCommand(player, "setLoopMode", ["loopMode": loop])
      let ended = expectation(description: "Empty playlist terminates with loop \(loop)")
      player.handleMethodCall(FlutterMethodCall(methodName: "play", arguments: [:])) { result in
        XCTAssertFalse(result is FlutterError)
        ended.fulfill()
      }
      // A command barrier makes the play/empty-track transition observable.
      _ = try portableCommand(player, "setVolume", ["volume": 1.0])
      for _ in 0..<16 {
        if events.last?["processingState"] as? Int == 4 { break }
        _ = try portableRender(player, frames: 4096)
      }
      wait(for: [ended], timeout: 3)
      XCTAssertEqual(events.last?["processingState"] as? Int, 4)
      if loop == 0 { XCTAssertTrue(events.contains { $0["currentIndex"] as? Int == 1 }) }
    }
  }

  private enum PortableTestError: Error { case native(String) }

  private func portableFile(_ url: URL, id: String) -> [String: Any] {
    ["type": "progressive", "id": id, "uri": url.absoluteString]
  }

  private func portablePlaylist(_ children: [[String: Any]]) -> [String: Any] {
    ["type": "concatenating", "id": "playlist", "children": children,
     "shuffleOrder": Array(children.indices)]
  }

  @discardableResult
  private func portableCommand(
    _ player: CrisperPortableAudioPlayer, _ method: String, _ arguments: [String: Any]
  ) throws -> Any? {
    let done = expectation(description: method)
    var response: Any?
    player.handleMethodCall(FlutterMethodCall(methodName: method, arguments: arguments)) {
      response = $0
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
    if let error = response as? FlutterError { throw PortableTestError.native(error.message ?? error.code) }
    return response
  }

  private func portableRender(_ player: CrisperPortableAudioPlayer, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
    let done = expectation(description: "Render native audio graph")
    var output: AVAudioPCMBuffer?
    var failure: Error?
    player.renderOffline(frames: frames) { buffer, error in
      output = buffer
      failure = error
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
    if let failure { throw failure }
    return try XCTUnwrap(output)
  }

  func testPortableNodeClockExcludesStarvationSilence() throws {
    let url = try makePortableFixture(frames: 144_000)
    defer { try? FileManager.default.removeItem(at: url) }
    var events: [[AnyHashable: Any]] = []
    let player = CrisperPortableAudioPlayer(engine: 0, manualRendering: true) { events.append($0) }
    defer { player.dispose(false) }
    _ = try portableCommand(player, "load", [
      "audioSource": portablePlaylist([portableFile(url, id: "book")]), "initialPosition": 0, "initialIndex": 0,
    ])
    player.handleMethodCall(FlutterMethodCall(methodName: "play", arguments: [:])) { _ in }
    // Queue renders before completion-refill jobs can run. The real graph
    // exhausts its four PCM buffers and renders silence until the worker
    // catches up; that silence must not count as listened-to source audio.
    _ = try portableRender(player, frames: 65_536)
    let position = try XCTUnwrap(events.last?["updatePosition"] as? Int)
    XCTAssertGreaterThan(position, 250_000)
    XCTAssertLessThan(position, 500_000, "Silent output gaps must not advance the source clock")
    XCTAssertEqual(events.last?["processingState"] as? Int, 2,
                   "Queued future audio must stay buffering until PCM resumes")
    // The refill jobs can queue new audio, but the manual device has not
    // rendered it yet; neither the source clock nor readiness may advance.
    _ = try portableCommand(player, "setVolume", ["volume": 1.0])
    XCTAssertEqual(events.last?["processingState"] as? Int, 2)
    XCTAssertEqual(events.last?["updatePosition"] as? Int, position)
    _ = try portableRender(player, frames: 4096)
    XCTAssertEqual(events.last?["processingState"] as? Int, 3,
                   "Readiness returns only after scheduled PCM is rendered")
    XCTAssertGreaterThan(try XCTUnwrap(events.last?["updatePosition"] as? Int), position)
    for _ in 0..<128 {
      if events.last?["processingState"] as? Int == 4 { break }
      _ = try portableRender(player, frames: 4096)
    }
    XCTAssertEqual(events.last?["processingState"] as? Int, 4)
    XCTAssertEqual(events.last?["updatePosition"] as? Int, 3_000_000)
  }

  func testPortableNodeRemovalCompletesOrSkipsEmptySuccessor() throws {
    let url = try makePortableFixture(frames: 9_600)
    defer { try? FileManager.default.removeItem(at: url) }
    for clearAll in [true, false] {
      var events: [[AnyHashable: Any]] = []
      let player = CrisperPortableAudioPlayer(engine: 0, manualRendering: true) { events.append($0) }
      defer { player.dispose(false) }
      let empty: [String: Any] = [
        "type": "clipping", "id": "empty", "start": 0, "end": 0,
        "child": portableFile(url, id: "empty-file"),
      ]
      _ = try portableCommand(player, "load", [
        "audioSource": portablePlaylist([
          portableFile(url, id: "current"), empty, portableFile(url, id: "successor"),
        ]), "initialPosition": 0, "initialIndex": 0,
      ])
      let ended = expectation(description: "Removal eventually completes active play")
      player.handleMethodCall(FlutterMethodCall(methodName: "play", arguments: [:])) { result in
        XCTAssertFalse(result is FlutterError)
        ended.fulfill()
      }
      _ = try portableCommand(player, "concatenatingRemoveRange", [
        "id": "playlist", "startIndex": 0, "endIndex": clearAll ? 3 : 1,
        "shuffleOrder": clearAll ? [] : [0, 1],
      ])
      if !clearAll {
        XCTAssertEqual(events.last?["currentIndex"] as? Int, 1,
                       "Removing the active track skips the empty successor")
        for _ in 0..<16 {
          if events.last?["processingState"] as? Int == 4 { break }
          _ = try portableRender(player, frames: 4096)
        }
      }
      wait(for: [ended], timeout: 3)
      XCTAssertEqual(events.last?["processingState"] as? Int, 4)
    }
  }
}
