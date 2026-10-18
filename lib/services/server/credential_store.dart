import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ServerCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class KeychainCredentialStore implements ServerCredentialStore {
  final String key;
  static const _channel = MethodChannel(
    'com.crispstrobe.crisperplayer/local-keychain',
  );
  static const _compiledKeychain = String.fromEnvironment(
    'CRISPERPLAYER_MACOS_KEYCHAIN',
  );
  final String? _macosKeychain;
  final FlutterSecureStorage _storage;
  KeychainCredentialStore({
    this.key = 'crisperplayer.remote.connections',
    String? macosKeychain,
  }) : _macosKeychain =
           macosKeychain ??
           (Platform.isMacOS
               ? (Platform.environment['CRISPERPLAYER_MACOS_KEYCHAIN'] ??
                     (_compiledKeychain.isEmpty ? null : _compiledKeychain))
               : null),
       _storage = Platform.isMacOS
           ? const FlutterSecureStorage(
               mOptions: MacOsOptions(usesDataProtectionKeychain: false),
             )
           : const FlutterSecureStorage(
               iOptions: IOSOptions(
                 accessibility: KeychainAccessibility.first_unlock_this_device,
               ),
             );
  @override
  Future<String?> read() => _macosKeychain == null
      ? _storage.read(key: key)
      : _channel.invokeMethod<String>('read', {
          'keychain': _macosKeychain,
          'key': key,
        });
  @override
  Future<void> write(String value) => _macosKeychain == null
      ? _storage.write(key: key, value: value)
      : _channel.invokeMethod<void>('write', {
          'keychain': _macosKeychain,
          'key': key,
          'value': value,
        });
  @override
  Future<void> delete() => _macosKeychain == null
      ? _storage.delete(key: key)
      : _channel.invokeMethod<void>('delete', {
          'keychain': _macosKeychain,
          'key': key,
        });
}
