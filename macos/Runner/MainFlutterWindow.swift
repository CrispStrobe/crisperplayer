import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var keychainChannel: FlutterMethodChannel?
  private let keychainQueue = DispatchQueue(label: "com.crispstrobe.crisperplayer.keychain")
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(name: "com.crispstrobe.crisperplayer/local-keychain",
                                       binaryMessenger: flutterViewController.engine.binaryMessenger)
    keychainChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard ["read", "write", "delete"].contains(call.method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let path = arguments["keychain"] as? String,
            let key = arguments["key"] as? String,
            call.method != "write" || arguments["value"] is String else {
        result(FlutterError(code: "invalid_keychain_request", message: "Invalid keychain request", details: nil))
        return
      }
      self?.keychainQueue.async {
        do {
          let store = try NamedKeychainStore(path: path)
          var value: String?
          switch call.method {
          case "read": value = try store.read(key)
          case "write": try store.write(key, value: arguments["value"] as! String)
          default: try store.delete(key)
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          let failure = error as NSError
          DispatchQueue.main.async {
            result(FlutterError(code: "named_keychain_\(failure.code)",
                                message: "Selected keychain: \(failure.localizedDescription)", details: nil))
          }
        }
      }
    }

    super.awakeFromNib()
  }
}
