import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:internxt_client/internxt_client.dart' as sdk;

/// Renews through the same authenticated endpoint used to hydrate login.
/// The published Dart SDK's refresh call omits the required CLI header.
/// The newer CLI-specific endpoint can reject accounts with HTTP 402.
class InternxtSessionClient extends sdk.InternxtClient {
  InternxtSessionClient({
    required super.config,
    http.Client Function()? refreshClient,
  }) : _refreshClient = refreshClient ?? http.Client.new;
  final http.Client Function() _refreshClient;
  Future<void>? _renewing;

  @override
  Future<void> refreshToken() =>
      _renewing ??= _renew().whenComplete(() => _renewing = null);

  Future<void> _renew() async {
    final current = await config.readCredentials();
    final token = current?['newToken'];
    if (current == null || token is! String || token.isEmpty) {
      throw const FormatException(
        'Reconnect the Internxt account to renew its session.',
      );
    }
    final client = _refreshClient();
    try {
      final request =
          http.Request('GET', Uri.parse('$driveApiUrl/users/refresh'))
            ..followRedirects = false
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'internxt-client': 'cli',
              'Content-Type': 'application/json',
            });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw sdk.ApiException(
          response.statusCode,
          'Internxt session renewal failed. Reconnect if the session was revoked.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Invalid renewal response.');
        }
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes)) as Map;
      final user = body['user'] as Map;
      final newToken = body['newToken'];
      final userId = user['userId'] ?? current['userId'];
      final bridgeUser = user['bridgeUser'];
      if (newToken is! String ||
          newToken.isEmpty ||
          userId is! String ||
          userId.isEmpty ||
          bridgeUser is! String ||
          bridgeUser.isEmpty ||
          current['userId'] != null && current['userId'] != userId) {
        throw const FormatException('Invalid Internxt session identity.');
      }
      final updated = <String, dynamic>{
        ...current,
        'token': body['token'] ?? body['oldToken'] ?? current['token'],
        'newToken': newToken,
        'bridgeUser': bridgeUser,
        'userIdForAuth': userId,
        'bridgePass': sha256.convert(utf8.encode(userId)).toString(),
        'rootFolderId': user['rootFolderId'] ?? current['rootFolderId'],
        'bucketId': user['bucket'] ?? current['bucketId'],
      };
      // ConfigStorage writes through to the app's secure credential store.
      await config.saveCredentials(updated);
      setAuth(updated);
    } finally {
      client.close();
    }
  }
}
