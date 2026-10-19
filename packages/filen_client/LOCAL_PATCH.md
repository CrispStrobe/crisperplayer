Vendored from `filen_client` 0.2.2 with the same macOS compatibility patch as CrispCloud.

OpenSSL probing is disabled on macOS: the app sandbox can abort the process when
Dart tries to load Homebrew libcrypto outside the app bundle. AES-GCM falls back
to `package:cryptography`, preserving the provider wire format. CrisperPlayer
uses its default backend; this patch does not promise CryptoKit acceleration.

The upstream MPL-2.0 license is preserved in LICENSE. The only library code
change is the macOS candidate list in lib/openssl_aesgcm.dart.
