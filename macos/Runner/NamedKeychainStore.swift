import Foundation
import Security

/// Uses only the explicitly selected classic keychain and this app's service.
/// Does not migrate items, search other keychains, or change system defaults.
final class NamedKeychainStore {
  private let keychain: SecKeychain
  private static let service = "com.crispstrobe.crisperplayer.server-credentials"

  init(path: String) throws {
    guard path.hasPrefix("/"), !path.contains("\0") else {
      throw Self.error(errSecParam)
    }
    var reference: SecKeychain?
    let status = SecKeychainOpen(path, &reference)
    guard status == errSecSuccess, let reference = reference else {
      throw Self.error(status)
    }
    var state: SecKeychainStatus = 0
    let statusCode = SecKeychainGetStatus(reference, &state)
    guard statusCode == errSecSuccess else { throw Self.error(statusCode) }
    guard state & SecKeychainStatus(kSecUnlockStateStatus) != 0 else {
      throw Self.error(errSecInteractionNotAllowed)
    }
    keychain = reference
  }

  private static func error(_ status: OSStatus) -> NSError {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain operation failed"
    return NSError(domain: "CrisperPlayer.NamedKeychain", code: Int(status),
                   userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func query(_ key: String) throws -> [String: Any] {
    guard !key.isEmpty, key.utf8.count <= 256 else { throw Self.error(errSecParam) }
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false,
            kSecMatchSearchList as String: [keychain],
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
  }

  func read(_ key: String) throws -> String? {
    var request = try query(key)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw Self.error(status) }
    guard let bytes = value as? Data, let text = String(data: bytes, encoding: .utf8) else {
      throw Self.error(errSecDecode)
    }
    return text
  }

  func write(_ key: String, value: String) throws {
    let bytes = Data(value.utf8)
    guard bytes.count <= 1024 * 1024 else { throw Self.error(errSecParam) }
    let request = try query(key)
    var status = SecItemUpdate(request as CFDictionary,
                              [kSecValueData as String: bytes] as CFDictionary)
    if status == errSecItemNotFound {
      var attributes = request
      attributes.removeValue(forKey: kSecMatchSearchList as String)
      attributes[kSecUseKeychain as String] = keychain
      attributes[kSecAttrLabel as String] = "CrisperPlayer server credentials"
      attributes[kSecValueData as String] = bytes
      status = SecItemAdd(attributes as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw Self.error(status) }
  }

  func delete(_ key: String) throws {
    let status = SecItemDelete(try query(key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
  }
}
