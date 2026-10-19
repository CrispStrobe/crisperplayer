import 'dart:convert';
import 'package:crisperplayer/services/server/internxt_session_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internxt_client/internxt_client.dart' as sdk;

void main() {
  test(
    'session renewal uses login hydration endpoint and CLI header and persists rotated bridge credentials once',
    () async {
      final storage = sdk.InMemoryConfigStorage();
      final config = sdk.ConfigService(
        configPath: '/unused-memory-config',
        storage: storage,
      );
      await config.saveCredentials({
        'newToken': 'old-token',
        'userId': 'test-user',
        'mnemonic': 'private fixture mnemonic',
        'rootFolderId': 'test-root',
      });
      var calls = 0;
      final client = InternxtSessionClient(
        config: config,
        refreshClient: () => MockClient((request) async {
          calls++;
          expect(request.url.path, '/drive/users/refresh');
          expect(request.headers['internxt-client'], 'cli');
          expect(request.headers['Authorization'], 'Bearer old-token');
          return http.Response(
            jsonEncode({
              'newToken': 'new-token',
              'user': {
                'userId': 'test-user',
                'bridgeUser': 'rotated-bridge-user',
              },
            }),
            200,
          );
        }),
      );
      await Future.wait([client.refreshToken(), client.refreshToken()]);
      final saved = (await config.readCredentials())!;
      expect(calls, 1);
      expect(saved['newToken'], 'new-token');
      expect(saved['mnemonic'], 'private fixture mnemonic');
      expect(saved['rootFolderId'], 'test-root');
      expect(client.bridgeUser, 'rotated-bridge-user');
      expect(client.userIdForAuth, 'test-user');
    },
  );

  test(
    'failed renewal preserves stored session and hides server response contents',
    () async {
      final config = sdk.ConfigService(
        configPath: '/unused-memory-config',
        storage: sdk.InMemoryConfigStorage(),
      );
      await config.saveCredentials({
        'newToken': 'old-token',
        'userId': 'test-user',
      });
      final client = InternxtSessionClient(
        config: config,
        refreshClient: () => MockClient(
          (_) async => http.Response('private server details', 401),
        ),
      );
      await expectLater(
        client.refreshToken(),
        throwsA(
          isA<sdk.ApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having(
                (e) => e.toString().contains('private server details'),
                'private body absent',
                false,
              ),
        ),
      );
      expect((await config.readCredentials())!['newToken'], 'old-token');
    },
  );
}
