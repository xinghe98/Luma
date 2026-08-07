import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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
import '../data/proxy/loopback_media_relay.dart';
import '../data/proxy/proxy_profile_store.dart';
import '../data/proxy/proxy_route.dart';
import '../data/proxy/vmess_proxy_controller.dart';
import '../data/proxy/vmess_proxy_profile.dart';
import '../data/proxy/xray_bridge.dart';
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
    VmessProxyController? proxyController,
    this.proxyRoute,
    ProxyHttpOverrides? proxyOverrides,
    this.mediaRelay,
    MediaRequestRouter? mediaRequestRouter,
  }) : media = MediaController(mediaRepository),
       session = SessionController(),
       settings = settingsController ?? SettingsController(),
       apiSession = apiSession ?? ApiSession(),
       catalog = CatalogStore(
         catalogRepository ?? const EmptyCatalogRepository(),
       ),
       access = accessRepository ?? const UnavailableAccessRepository(),
       sources = sourceRepository,
       proxy = proxyController,
       _proxyOverrides = proxyOverrides,
       _mediaRequestRouter =
           mediaRequestRouter ?? mediaRelay ?? const DirectMediaRequestRouter(),
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
      mediaRequestRouter: _mediaRequestRouter,
    );
    connection = ConnectionController(
      connectionService: connectionService,
      sessionController: session,
      mediaController: media,
      isProxyActive: () => proxy?.isActive ?? false,
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
    final proxyRoute = ProxyRoute();
    final proxyOverrides = ProxyHttpOverrides(proxyRoute)..install();
    final xrayBridge = XrayBridge();
    final proxyController = VmessProxyController(
      store: SecureProxyProfileStore(const FlutterSecureStorage()),
      parser: VmessProfileParser(xrayBridge),
      bridge: xrayBridge,
      route: proxyRoute,
    );
    final apiSession = ApiSession();
    final mediaRelay = LoopbackMediaRelay(
      proxyRoute: proxyRoute,
      createHttpClient: () => proxyOverrides.newClient(),
      authorizationHeadersFor: apiSession.authorizationHeadersFor,
    );
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 10),
      ),
    )..interceptors.add(ApiSessionInterceptor(apiSession));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => proxyOverrides.newClient(),
    );
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
      activeProxyProfileId: () => proxyController.activeProfileId,
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
      proxyController: proxyController,
      proxyRoute: proxyRoute,
      proxyOverrides: proxyOverrides,
      mediaRelay: mediaRelay,
    );
  }

  static Future<AppDependencies> production() async {
    final dependencies = create();
    await dependencies.initialize();
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
  final VmessProxyController? proxy;
  final ProxyRoute? proxyRoute;
  final ProxyHttpOverrides? _proxyOverrides;
  final LoopbackMediaRelay? mediaRelay;
  final MediaRequestRouter _mediaRequestRouter;
  late final ConnectionController connection;

  /// 恢复旧会话期间禁止新的连接尝试，避免两个请求改写同一 ApiSession。
  final ValueNotifier<bool> restoring = ValueNotifier(false);
  int _restoreOperation = 0;
  bool _disposed = false;
  StoredCredentials? _pendingProxyRestore;

  /// 依赖容器是否已释放；主要供宿主生命周期与测试断言使用。
  bool get isDisposed => _disposed;

  bool get canConfigureProxy =>
      !_disposed &&
      session.server == null &&
      !connection.isLoading &&
      !restoring.value;

  Future<void> initialize() async {
    if (_disposed) return;
    await mediaRelay?.start();
    if (_disposed) return;
    await proxy?.load();
  }

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
      if (saved.proxyProfileId != null) {
        final controller = proxy;
        if (controller == null ||
            controller.activeProfileId != saved.proxyProfileId) {
          _pendingProxyRestore = saved;
          return false;
        }
      }
      _pendingProxyRestore = null;
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

  Future<bool> startProxy() async {
    if (!canConfigureProxy) return false;
    final controller = proxy;
    if (controller == null) return false;
    await controller.start();
    if (_disposed || !controller.isActive) return false;
    final pending = _pendingProxyRestore;
    if (pending == null ||
        pending.proxyProfileId != controller.activeProfileId ||
        pending.sessionToken == null) {
      return true;
    }
    restoring.value = true;
    try {
      final restored = await connection.restore(
        pending.origin,
        pending.sessionToken!,
      );
      if (!_disposed && restored) _pendingProxyRestore = null;
      return !_disposed && restored;
    } finally {
      if (!_disposed) restoring.value = false;
    }
  }

  Future<void> stopProxy() async {
    if (!canConfigureProxy) return;
    await proxy?.stop();
  }

  Future<void> importProxyProfile(String clipboardText) async {
    if (!canConfigureProxy) return;
    final controller = proxy;
    if (controller == null) return;
    final previousId = controller.profile?.id;
    await controller.importFromClipboard(clipboardText);
    if (controller.profile?.id != previousId) _pendingProxyRestore = null;
  }

  Future<void> deleteProxyProfile() async {
    if (!canConfigureProxy) return;
    await proxy?.deleteProfile();
    _pendingProxyRestore = null;
  }

  /// 结束当前服务器会话并清空所有会话级缓存；销毁期间会安全停止。
  Future<void> disconnect() async {
    if (_disposed) return;
    _restoreOperation++;
    restoring.value = false;
    await playerSession.close(invalidateCatalog: false);
    if (_disposed) return;

    Object? disconnectError;
    StackTrace? disconnectStack;
    try {
      await _connectionService.disconnect();
    } on Object catch (error, stackTrace) {
      disconnectError = error;
      disconnectStack = stackTrace;
    } finally {
      if (!_disposed) {
        session.disconnect();
        mediaRelay?.revokeAll();
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
      }
    }
    if (disconnectError != null) {
      Error.throwWithStackTrace(disconnectError, disconnectStack!);
    }
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
    _proxyOverrides?.restore();
    proxyRoute?.deactivate();
    mediaRelay?.revokeAll();
    unawaited(mediaRelay?.close());
    final proxyController = proxy;
    if (proxyController != null) unawaited(proxyController.disposeProxy());
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
