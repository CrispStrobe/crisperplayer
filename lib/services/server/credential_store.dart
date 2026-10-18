import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ServerCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class KeychainCredentialStore implements ServerCredentialStore {
  final String key;
  final FlutterSecureStorage _storage;
  KeychainCredentialStore({this.key = 'crisperplayer.remote.connections'})
    : _storage = Platform.isMacOS
          ? const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            )
          : const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );
  @override
  Future<String?> read() => _storage.read(key: key);
  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: key);
}
