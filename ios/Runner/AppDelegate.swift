import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var transferChannel: FlutterMethodChannel?
  private var previousIdleTimer: Bool?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ForegroundTransfer") {
      let channel = FlutterMethodChannel(name: "com.crispstrobe.crisperplayer/transfer",
        binaryMessenger: registrar.messenger())
      transferChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        guard call.method == "keepAwake" else { result(FlutterMethodNotImplemented); return }
        if call.arguments as? Bool == true {
          if self.previousIdleTimer == nil { self.previousIdleTimer = UIApplication.shared.isIdleTimerDisabled }
          UIApplication.shared.isIdleTimerDisabled = true
        } else if let previous = self.previousIdleTimer {
          UIApplication.shared.isIdleTimerDisabled = previous
          self.previousIdleTimer = nil
        }
        result(nil)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CompanionBridge") {
      CompanionBridge.shared.install(messenger: registrar.messenger())
    }
  }
}

// Companion surfaces reuse the Flutter playback service through one narrow
// bridge; no credentials or library database are shared with extensions.
import CarPlay
import WatchConnectivity
import WidgetKit

final class CompanionBridge: NSObject, WCSessionDelegate {
  static let shared = CompanionBridge()
  private var channel: FlutterMethodChannel?
  private var ready = false
  private var pending: [String: Any]?
  private var snapshot: [String: Any] = [:]
  private var lastWatchUpdate = Date.distantPast
  private var lastWidgetUpdate = Date.distantPast
  private let group = "group.com.crispstrobe.crisperplayer"

  func install(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.crispstrobe.crisperplayer/companion", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "ready":
        self.ready = true
        let action = self.pending
        self.pending = nil
        result(action)
      case "update":
        if let data = call.arguments as? [String: Any] { self.update(data) }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }
  func open(_ url: URL) -> Bool {
    guard url.scheme == "crisperplayer", url.host == "control" else { return false }
    let action = url.lastPathComponent
    guard ["play", "pause", "toggle", "backward", "forward"].contains(action) else { return false }
    let payload: [String: Any] = ["action": action]
    if ready { command(payload) { _ in } } else { pending = payload }
    return true
  }
  func command(_ payload: [String: Any], completion: @escaping (Any?) -> Void) {
    guard ready, let channel else {
      completion(FlutterError(code: "not_ready", message: "Open CrisperPlayer on your iPhone first.", details: nil)); return
    }
    channel.invokeMethod("command", arguments: payload, result: completion)
  }
  func browse(_ parent: String, completion: @escaping ([[String: Any]]) -> Void) {
    guard ready, let channel else { completion([]); return }
    channel.invokeMethod("browse", arguments: ["parent": parent]) { result in
      completion(result as? [[String: Any]] ?? [])
    }
  }
  private func update(_ data: [String: Any]) {
    let changed = (snapshot["title"] as? String) != (data["title"] as? String) ||
      (snapshot["author"] as? String) != (data["author"] as? String) ||
      (snapshot["playing"] as? Bool) != (data["playing"] as? Bool)
    snapshot = data
    if changed || Date().timeIntervalSince(lastWidgetUpdate) >= 900 {
      lastWidgetUpdate = Date()
      if let defaults = UserDefaults(suiteName: group) {
        defaults.set(data, forKey: "playerSnapshot")
        WidgetCenter.shared.reloadTimelines(ofKind: "CrisperPlayerWidget")
      }
    }
    if WCSession.isSupported(), WCSession.default.activationState == .activated,
       WCSession.default.isWatchAppInstalled,
       changed || Date().timeIntervalSince(lastWatchUpdate) >= 30 {
      lastWatchUpdate = Date()
      try? WCSession.default.updateApplicationContext(data)
    }
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.lastWatchUpdate = .distantPast; self.update(self.snapshot) }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async {
      if message["action"] as? String == "snapshot" { replyHandler(self.snapshot); return }
      self.command(message) { result in
        if let error = result as? FlutterError { replyHandler(["error": error.message ?? "Command failed"]) }
        else { replyHandler(result as? [String: Any] ?? self.snapshot) }
      }
    }
  }
}

// The audio entitlement is managed by Apple. This scene can be tested in the
// CarPlay simulator; signed distribution must wait for Apple's approval.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var controller: CPInterfaceController?
  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                               didConnect interfaceController: CPInterfaceController) {
    controller = interfaceController
    show("root", title: "CrisperPlayer", root: true)
  }
  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                               didDisconnect interfaceController: CPInterfaceController) {
    controller = nil
  }
  private func show(_ parent: String, title: String, root: Bool = false) {
    CompanionBridge.shared.browse(parent) { [weak self] rows in
      guard let self, let controller = self.controller else { return }
      let items = rows.map { row -> CPListItem in
        let item = CPListItem(text: row["title"] as? String, detailText: row["subtitle"] as? String)
        item.handler = { [weak self] _, done in
          guard let id = row["id"] as? String else { done(); return }
          if row["playable"] as? Bool == true {
            CompanionBridge.shared.command(["action": "play", "mediaId": id]) { result in
              if let error = result as? FlutterError {
                let alert = CPAlertTemplate(titleVariants: [error.message ?? "Could not play this book"],
                  actions: [CPAlertAction(title: "OK", style: .default) { _ in controller.dismissTemplate(animated: true, completion: nil) }])
                controller.presentTemplate(alert, animated: true, completion: nil)
              } else { controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil) }
              done()
            }
          } else { self?.show(id, title: row["title"] as? String ?? "Books"); done() }
        }
        return item
      }
      let section = CPListSection(items: items.isEmpty ? [CPListItem(text: "Open CrisperPlayer on your iPhone", detailText: "Add or download an audiobook first.")] : items)
      let template = CPListTemplate(title: title, sections: [section])
      if root { controller.setRootTemplate(template, animated: true, completion: nil) }
      else { controller.pushTemplate(template, animated: true, completion: nil) }
    }
  }
}
