import Flutter
import UIKit
import receive_sharing_intent

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      if CompanionBridge.shared.open(context.url) { continue }
      _ = SwiftReceiveSharingIntentPlugin.instance.application(
        UIApplication.shared,
        didFinishLaunchingWithOptions: [UIApplication.LaunchOptionsKey.url: context.url])
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      if CompanionBridge.shared.open(context.url) { continue }
      if SwiftReceiveSharingIntentPlugin.instance.hasMatchingSchemePrefix(url: context.url) {
        _ = SwiftReceiveSharingIntentPlugin.instance.application(
          UIApplication.shared, open: context.url, options: [:])
      }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
