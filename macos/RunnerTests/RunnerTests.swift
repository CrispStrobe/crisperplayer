import AVFoundation
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
}
