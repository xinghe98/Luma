import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/api/api_client.dart';
import '../data/api/api_session.dart';
import '../data/api/api_session_interceptor.dart';
import '../data/repositories/access_repository.dart';
import '../data/repositories/api_access_repository.dart';
import '../data/repositories/api_media_repository.dart';
import '../data/repositories/api_catalog_repository.dart';
import '../data/repositories/api_scan_repository.dart';
import '../data/repositories/api_source_repository.dart';
import '../data/repositories/media_repository.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/source_repository.dart';
import '../data/services/api_connection_service.dart';
import '../data/services/connection_service.dart';
import '../data/storage/credential_store.dart';
import '../data/storage/secure_credential_store.dart';
import '../data/storage/secure_server_alias_store.dart';
import '../data/storage/server_alias_store.dart';
import '../features/connection/connection_controller.dart';
import '../features/player/player_session_controller.dart';
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
    CredentialStore? credentialStore,
    ServerAliasStore? aliasStore,
    CatalogRepository? catalogRepository,
    SourceRepository? sourceRepository,
    AccessRepository? accessRepository,
  }) : media = MediaController(mediaRepository),
       session = SessionController(),
       settings = settingsController ?? SettingsController(),
       apiSession = apiSession ?? ApiSession(),
       catalog = catalogRepository ?? const EmptyCatalogRepository(),
       access = accessRepository ?? const UnavailableAccessRepository(),
       sources = sourceRepository,
       _connectionService = connectionService,
       _credentialStore = credentialStore,
       _aliasStore = aliasStore,
       _dio = dio {
    playerSession = PlayerSessionController(
      media: media,
      apiSession: this.apiSession,
    );
    connection = ConnectionController(
      connectionService: connectionService,
      sessionController: session,
      mediaController: media,
      onConnected: () async {
        final server = session.server;
        if (server != null && server.can('scans.manage')) {
          await settings.restoreScan();
        }
      },
    );
  }

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
      aliasStore: aliases,
      sourceRepository: sources,
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
      catalogRepository: ApiCatalogRepository(client),
      sourceRepository: sources,
      accessRepository: ApiAccessRepository(client),
    );
  }

  static Future<AppDependencies> production() async {
    final dependencies = create();
    await dependencies.restoreSession();
    return dependencies;
  }

  final MediaController media;
  final SessionController session;
  final SettingsController settings;
  final ApiSession apiSession;
  late final PlayerSessionController playerSession;
  final CatalogRepository catalog;
  final AccessRepository access;
  final SourceRepository? sources;
  final ConnectionService _connectionService;
  final CredentialStore? _credentialStore;
  final ServerAliasStore? _aliasStore;
  final Dio? _dio;
  late final ConnectionController connection;

  /// 恢复旧会话期间禁止新的连接尝试，避免两个请求改写同一 ApiSession。
  final ValueNotifier<bool> restoring = ValueNotifier(false);
  int _restoreOperation = 0;

  Future<bool> restoreSession() async {
    final store = _credentialStore;
    if (store == null) return false;
    final operation = ++_restoreOperation;
    restoring.value = true;
    try {
      final saved = await store.read();
      if (operation != _restoreOperation ||
          saved == null ||
          saved.sessionToken == null) {
        return false;
      }
      final restored = await connection.restore(
        saved.origin,
        saved.sessionToken!,
      );
      return operation == _restoreOperation && restored;
    } finally {
      if (operation == _restoreOperation) restoring.value = false;
    }
  }

  Future<void> disconnect() async {
    _restoreOperation++;
    restoring.value = false;
    session.disconnect();
    await playerSession.close();
    media.clear();
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    if (sources case SessionResettableSourceRepository resettable) {
      resettable.clearSessionCache();
    }
    settings.resetConnection();
    connection.reset();
    await _connectionService.disconnect();
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
    playerSession.dispose();
    connection.dispose();
    media.dispose();
    session.dispose();
    settings.dispose();
    restoring.dispose();
    _dio?.close(force: true);
  }
}
