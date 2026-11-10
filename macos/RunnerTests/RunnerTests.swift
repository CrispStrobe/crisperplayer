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
}
