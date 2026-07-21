import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/api/api_client.dart';
import '../data/api/api_session.dart';
import '../data/api/api_session_interceptor.dart';
import '../data/repositories/api_media_repository.dart';
import '../data/repositories/api_scan_repository.dart';
import '../data/repositories/api_source_repository.dart';
import '../data/repositories/media_repository.dart';
import '../data/services/api_connection_service.dart';
import '../data/services/connection_service.dart';
import '../data/storage/secure_credential_store.dart';
import '../data/storage/secure_server_alias_store.dart';
import '../data/storage/server_alias_store.dart';
import '../features/connection/connection_controller.dart';
import 'controllers/media_controller.dart';
import 'controllers/session_controller.dart';
import 'controllers/settings_controller.dart';

class AppDependencies {
  AppDependencies({
    required MediaRepository mediaRepository,
    required ConnectionService connectionService,
    ApiSession? apiSession,
    SettingsController? settingsController,
    Dio? dio,
    SecureCredentialStore? credentialStore,
    ServerAliasStore? aliasStore,
  }) : media = MediaController(mediaRepository),
       session = SessionController(),
       settings = settingsController ?? SettingsController(),
       apiSession = apiSession ?? ApiSession(),
       _connectionService = connectionService,
       _credentialStore = credentialStore,
       _aliasStore = aliasStore,
       _dio = dio {
    connection = ConnectionController(
      connectionService: connectionService,
      sessionController: session,
      mediaController: media,
      onConnected: settings.restoreScan,
    );
  }

  /// Builds application-scoped dependencies without blocking on restore.
  static AppDependencies create() {
    const apiPrefix = String.fromEnvironment(
      'LUMA_API_PREFIX',
      defaultValue: ApiClient.defaultApiPrefix,
    );
    final apiSession = ApiSession();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 10),
      ),
    )..interceptors.add(ApiSessionInterceptor(apiSession));
    final client = ApiClient(dio, apiPrefix: apiPrefix);
    const secureStorage = FlutterSecureStorage();
    final credentials = SecureCredentialStore(secureStorage);
    final aliases = SecureServerAliasStore(secureStorage);
    final sources = ApiSourceRepository(client);
    final connectionService = ApiConnectionService(
      client: client,
      apiSession: apiSession,
      credentialStore: credentials,
      sourceRepository: sources,
      aliasStore: aliases,
    );
    return AppDependencies(
      mediaRepository: ApiMediaRepository(client, sources),
      connectionService: connectionService,
      apiSession: apiSession,
      settingsController: SettingsController(
        scanRepository: ApiScanRepository(client, sources),
      ),
      dio: dio,
      credentialStore: credentials,
      aliasStore: aliases,
    );
  }

  /// Creates dependencies and restores a saved session when possible.
  static Future<AppDependencies> production() async {
    final dependencies = create();
    await dependencies.restoreSession();
    return dependencies;
  }

  final MediaController media;
  final SessionController session;
  final SettingsController settings;
  final ApiSession apiSession;
  final ConnectionService _connectionService;
  final SecureCredentialStore? _credentialStore;
  final ServerAliasStore? _aliasStore;
  final Dio? _dio;
  late final ConnectionController connection;
  /// 恢复旧会话期间禁止新的连接尝试，避免两个请求改写同一 ApiSession。
  final ValueNotifier<bool> restoring = ValueNotifier(false);

  Future<bool> restoreSession() async {
    final store = _credentialStore;
    if (store == null) return false;
    restoring.value = true;
    try {
      final saved = await store.read();
      if (saved == null || saved.token == null) return false;
      final restored = await connection.restore(saved.origin, saved.token!);
      return restored;
    } finally {
      restoring.value = false;
    }
  }

  Future<void> disconnect() async {
    await _connectionService.disconnect();
    session.disconnect();
    media.clear();
    settings.resetConnection();
    connection.reset();
  }

  Future<void> updateServerAlias(String value) async {
    final server = session.server;
    final store = _aliasStore;
    if (server == null || store == null) return;
    final alias = value.trim();
    if (alias.isEmpty) {
      await store.clear(server.address);
      session.rename(server.hostName);
    } else {
      await store.write(server.address, alias);
      session.rename(alias);
    }
  }

  void dispose() {
    connection.dispose();
    media.dispose();
    session.dispose();
    settings.dispose();
    restoring.dispose();
    _dio?.close(force: true);
  }
}
