# Store listing and production preparation

App: **CrisperPlayer** · iOS ID **6824160419** · bundle
`com.crispstrobe.crisperplayer` · minimum iOS **15.0**.
Internal TestFlight and GitHub releases are separate from a public App Store
submission. This document is draft listing copy, not a claim of review approval.

## Subtitle / short description

Your audiobooks, your place.

## Description

Listen to your own audiobooks, keep your place and organize your library.
Import local audio or download books from Plex, Filen, Internxt, Nextcloud,
WebDAV, SFTP and SMB for offline listening.

- M4B/M4A, MP3, FLAC, Ogg, Opus, WAV and other formats supported by your device.
- Embedded chapters, bookmarks and notes, editable book details and covers.
- Series, collections, reading status and a persistent Up next queue.
- Per-book speed, smart rewind, configurable skips and a custom sleep timer.
- Background playback and system media controls on Android/iOS.
- Editable timecode, volume control and measured audio waveforms generated locally.
- Optional Plex progress sync and encrypted progress files in your own cloud folder.
- Keyboard shortcuts and a desktop CLI using the same player services.
- No advertising or tracking. Local listening works without a CrisperPlayer account.

Codec and platform features vary. Voice boost and equalizer are Android features.
Browser listening has a smaller local-file feature set. CarPlay, iOS widgets and
Watch require separate provisioning and device validation; do not advertise them
as shipped in a build that does not include the corresponding entitlement/target.
The Watch companion controls the iPhone and does not play audio independently.

## Links

- Website: https://crispstrobe.github.io/crisperplayer/
- Support: https://github.com/CrispStrobe/crisperplayer/issues
- Privacy: https://github.com/CrispStrobe/crisperplayer/blob/master/PRIVACY.md
- Source / AGPL-3.0: https://github.com/CrispStrobe/crisperplayer

## Public App Store preparation

Before attaching a tested internal build to a public submission:

1. Review the description above against the exact build. Populate localized
   description, subtitle, keywords and support/privacy URLs in App Store Connect.
2. Capture real iPhone/iPad simulator/device screenshots of library, compact
   player, chapters, bookmarks and cloud-source setup without private credentials.
   Keep required device classes/resolutions current with App Store Connect.
3. Complete the App Privacy form in App Store Connect. The form is browser-only
   per the shared `../appstore.md` protocol. Describe optional user-configured
   provider/sync traffic accurately; do not reuse the old “no network access” copy.
4. Verify age rating, export-compliance answers, pricing, territories, review
   contact and app review instructions. Standard encrypted transports and SDKs
   are included; confirm the appropriate questionnaire for the delivered build.
5. Attach the exact VALID iOS build, review its internal feedback and perform
   device acceptance testing. Public submission/release is a separate action.

Do not create/revoke signing certificates or modify an existing App ID's
capabilities as part of listing preparation. Companion signing requirements are
in [COMPANIONS.md](docs/COMPANIONS.md); distribution is in [RELEASES.md](docs/RELEASES.md).

The editable App Store Connect draft was updated to version **0.1.0** with the
verified English copy in [docs/store/en-US](docs/store/en-US/description.txt),
subtitle, keywords, copyright and support/privacy/website URLs. Its state remains
**PREPARE_FOR_SUBMISSION**. No review submission or public release was performed.
`scripts/prepare_appstore.py` verifies the app identity and editable state before
applying that copy and reading it back. All ten real iPhone/iPad screenshots
are attached and Apple reports them complete. Validated build 18 is attached to
the 0.1.0 draft, which remains PREPARE_FOR_SUBMISSION. Privacy-form completion
and device acceptance checks remain production-preparation steps.
