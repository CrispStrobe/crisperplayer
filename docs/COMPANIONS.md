# Car interfaces, widgets and Watch

All commands use the native app's existing playback coordinator. There is no
second player, separate progress database or credential store in a companion.

## Android Auto and home-screen widget

The audio_service browser exposes Continue listening, Library, Up next and book
chapters. Voice search queries titles/authors. Browsing is bounded to 100 items
per branch. Media IDs are validated against the local database. Only imported
or downloaded books appear; car browsing does not access cloud credentials.

The Android media-browser service and automotive media descriptor are registered.
The app's **CrisperPlayer** home-screen widget shows the book and author and opens
the app to play/pause or skip ±30 seconds. Actions wait for app startup before
using the normal playback service. Updates follow playback changes. Validate with
Android Auto Desktop Head Unit and a real phone/head unit before claiming device
certification; lock-screen controls alone are not an Android Auto test.

## CarPlay

The iOS host contains the CarPlay audio scene, browse tree, chapter selection,
resume and system Now Playing presentation. Distribution needs Apple's managed
`com.apple.developer.carplay-audio` entitlement. Request it at
[Apple Developer](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements).
Do not add an unauthorized entitlement or mutate existing capabilities/profiles.
Once Apple approves it, regenerate the host App Store profile against the existing
canonical certificate and update `IOS_PROFILE_APP_BASE64`. The signing installer
adds the entitlement only if that validated profile authorizes it.

## iOS widget and Apple Watch

Source and a reproducible standalone XcodeGen project are in `ios/Companions`.
`apple-companions.yml` builds both targets independently without signing and
validates the idempotent host-embedding script. These builds are verification
artifacts; they do not claim a provisioned TestFlight extension.

The iOS medium widget uses the existing app group
`group.com.crispstrobe.crisperplayer` for a small title/author/play-state snapshot.
Its links open the app for play/pause and ±30-second skips. WidgetKit controls
refresh timing; it is not a live elapsed-time display.

The Watch companion remotely controls the iPhone's play/pause, ±30-second skips
and chapter navigation through WatchConnectivity, with encrypted OS-managed
transport. It shows the latest title/author/position and a connection error when
the iPhone cannot be reached. Commands are never replayed later after a failed
connection. This version has **no standalone Watch audio downloads/playback**.

To include signed companions in internal TestFlight:

1. Register `com.crispstrobe.crisperplayer.PlayerWidget` and
   `com.crispstrobe.crisperplayer.watchkitapp` as explicit identifiers.
2. In the Developer portal, associate **PlayerWidget** with the existing app
   group. App Group creation/association is browser-only per `../appstore.md`;
   enabling the capability via API alone gives an empty entitlement and is
   insufficient. Do not invalidate the existing Runner/ShareExtension profiles.
3. Create App Store profiles for those identifiers using the existing canonical
   Distribution certificate. Save them as `IOS_PROFILE_WIDGET_BASE64` and
   `IOS_PROFILE_WATCH_BASE64` GitHub secrets. Watch needs no app-group entitlement.
4. The TestFlight workflow validates optional profiles before adding the selected
   targets with `scripts/configure_apple_companions.rb --widget --watch`, then
   archives/exports and verifies the included bundles. Their versions follow
   the root pubspec, not a hard-coded companion version.
5. Test pairing, reachability, cold starts and widget links on actual devices.

For local unsigned verification:

```sh
xcodegen generate --spec ios/Companions/project.yml
xcodebuild -project ios/Companions/CrisperPlayerCompanions.xcodeproj \
  -scheme PlayerWidget -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Companions/CrisperPlayerCompanions.xcodeproj \
  -scheme PlayerWatch -sdk watchsimulator CODE_SIGNING_ALLOWED=NO build
```

Xcode must have the matching Watch platform installed. Native source can also be
type-checked with `swiftc` against the Watch SDK when its build destination is
unavailable. A successful type-check is not a full build or live pairing test.
