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
import '../features/catalog/catalog_store.dart';
import '../features/player/player_session_controller.dart';
import '../features/shell/media_branch_prewarmer.dart';
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
       catalog = CatalogStore(
         catalogRepository ?? const EmptyCatalogRepository(),
       ),
       access = accessRepository ?? const UnavailableAccessRepository(),
       sources = sourceRepository,
       _connectionService = connectionService,
       _credentialStore = credentialStore,
       _aliasStore = aliasStore,
       _dio = dio {
    mediaBranchPrewarmer = MediaBranchPrewarmer(
      media: media,
      catalog: catalog,
      session: this.apiSession,
    );
    playerSession = PlayerSessionController(
      media: media,
      apiSession: this.apiSession,
      onCatalogInvalidated: catalog.invalidate,
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
  final CatalogStore catalog;
  late final MediaBranchPrewarmer mediaBranchPrewarmer;
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
  bool _disposed = false;

  /// 依赖容器是否已释放；主要供宿主生命周期与测试断言使用。
  bool get isDisposed => _disposed;

  /// 尝试恢复保存的会话；读取或连接失败时返回 false，销毁后不再发布状态。
  Future<bool> restoreSession() async {
    if (_disposed) return false;
    final store = _credentialStore;
    if (store == null) return false;
    final operation = ++_restoreOperation;
    if (!_disposed) restoring.value = true;
    try {
      final saved = await store.read();
      if (_disposed ||
          operation != _restoreOperation ||
          saved == null ||
          saved.sessionToken == null) {
        return false;
      }
      final restored = await connection.restore(
        saved.origin,
        saved.sessionToken!,
      );
      return !_disposed && operation == _restoreOperation && restored;
    } on Object {
      return false;
    } finally {
      if (!_disposed && operation == _restoreOperation) restoring.value = false;
    }
  }

  /// 结束当前服务器会话并清空所有会话级缓存；销毁期间会安全停止。
  Future<void> disconnect() async {
    if (_disposed) return;
    _restoreOperation++;
    restoring.value = false;
    session.disconnect();
    await playerSession.close(invalidateCatalog: false);
    if (_disposed) return;
    mediaBranchPrewarmer.reset();
    media.clear();
    catalog.clear();
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

  /// 保存当前服务器的本地别名；容器销毁后忽略尚未完成的写入结果。
  Future<void> updateServerAlias(String value) async {
    if (_disposed) return;
    final server = session.server;
    final store = _aliasStore;
    if (server == null || store == null) return;
    final alias = value.trim();
    if (alias.isEmpty) {
      await store.clear(server.address);
      if (_disposed) return;
      session.rename(server.hostName);
    } else {
      await store.write(server.address, alias);
      if (_disposed) return;
      session.rename(alias);
    }
  }

  /// 释放应用级控制器、共享 store 与生产环境网络客户端。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _restoreOperation++;
    playerSession.dispose();
    connection.dispose();
    mediaBranchPrewarmer.dispose();
    media.dispose();
    session.dispose();
    settings.dispose();
    catalog.dispose();
    restoring.dispose();
    _dio?.close(force: true);
  }
}
