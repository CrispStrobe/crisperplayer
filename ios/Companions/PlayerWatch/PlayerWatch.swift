import SwiftUI
import WatchConnectivity

final class WatchPlayer: NSObject, ObservableObject, WCSessionDelegate {
  @Published var title = "CrisperPlayer"
  @Published var author = "Open the iPhone app"
  @Published var playing = false
  @Published var position = 0
  @Published var error: String?
  override init() {
    super.init()
    if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
  }
  private func apply(_ data: [String: Any]) {
    if let message = data["error"] as? String { error = message; return }
    error = nil
    title = data["title"] as? String ?? title
    author = data["author"] as? String ?? author
    playing = data["playing"] as? Bool ?? playing
    position = data["position"] as? Int ?? position
  }
  func command(_ action: String) {
    guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
      error = "Open CrisperPlayer on your iPhone to control playback."; return
    }
    WCSession.default.sendMessage(["action": action], replyHandler: { data in
      DispatchQueue.main.async { self.apply(data) }
    }, errorHandler: { _ in
      DispatchQueue.main.async { self.error = "iPhone unavailable. Try again when connected." }
    })
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.apply(session.receivedApplicationContext); self.command("snapshot") }
  }
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    DispatchQueue.main.async { self.apply(applicationContext) }
  }
}
@main
struct PlayerWatchApp: App {
  @StateObject private var player = WatchPlayer()
  var body: some Scene {
    WindowGroup {
      ScrollView {
        VStack(spacing: 10) {
          Text(player.title).font(.headline).multilineTextAlignment(.center)
          Text(player.author).font(.caption).foregroundStyle(.secondary)
          Text(String(format: "%d:%02d", player.position / 60, player.position % 60)).monospacedDigit()
          HStack {
            Button { player.command("backward") } label: { Image(systemName: "gobackward.30") }.accessibilityLabel("Back 30 seconds")
            Button { player.command(player.playing ? "pause" : "play") } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill") }.accessibilityLabel(player.playing ? "Pause" : "Play")
            Button { player.command("forward") } label: { Image(systemName: "goforward.30") }.accessibilityLabel("Forward 30 seconds")
          }
          HStack {
            Button("Previous chapter") { player.command("previousChapter") }
            Button("Next chapter") { player.command("nextChapter") }
          }.font(.caption)
          Button("Refresh") { player.command("snapshot") }.font(.caption)
          if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.horizontal, 4)
      }
    }
  }
}
