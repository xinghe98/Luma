import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/api_session.dart';
import '../decoders/system_info_decoder.dart';
import '../models/server_profile.dart';
import '../repositories/api_source_repository.dart';
import '../repositories/source_repository.dart';
import '../storage/credential_store.dart';
import '../storage/server_alias_store.dart';
import 'connection_service.dart';
import 'device_key_store.dart';
import 'device_name_resolver.dart';

final class ApiConnectionService implements ConnectionService {
  ApiConnectionService({
    required ApiClient client,
    required ApiSession apiSession,
    required CredentialStore credentialStore,
    required ServerAliasStore aliasStore,
    SourceRepository? sourceRepository,
    DeviceNameResolver? deviceNameResolver,
    DeviceKeyStore? deviceKeyStore,
  }) : _client = client,
       _apiSession = apiSession,
       _credentialStore = credentialStore,
       _aliasStore = aliasStore,
       _sourceRepository = sourceRepository,
       _deviceNameResolver = deviceNameResolver ?? PlatformDeviceNameResolver(),
       _deviceKeyStore = deviceKeyStore ?? SecureDeviceKeyStore();

  final ApiClient _client;
  final ApiSession _apiSession;
  final CredentialStore _credentialStore;
  final ServerAliasStore _aliasStore;
  final SourceRepository? _sourceRepository;
  final DeviceNameResolver _deviceNameResolver;
  final DeviceKeyStore _deviceKeyStore;
  final SystemInfoDecoder _systemDecoder = const SystemInfoDecoder();
  int _operation = 0;
  Future<void> _credentialQueue = Future<void>.value();

  static const _logoutTimeout = Duration(seconds: 2);

  @override
  ServerProfile? connectedProfile;

  @override
  /// 验证服务地址和账号后建立候选会话，凭据安全落盘成功后才发布为全局会话。
  /// 服务不可达、存储失败或并发操作使候选过期时返回失败，并尽量撤销候选会话。
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async {
    final operation = ++_operation;
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    if (credentials.username.trim().isEmpty || credentials.password.isEmpty) {
      return ConnectionResult.unauthorized;
    }

    final origin = normalizeOrigin(uri);
    final unauthenticated = _client.isolatedFor(ApiSession(origin: origin));
    try {
      final deviceName = await _deviceNameResolver.resolve();
      final deviceKey = await _deviceKeyStore.readOrCreate();
      if (operation != _operation) return ConnectionResult.unreachable;
      final health = await unauthenticated.getHealth();
      final login = await _loginCompatible(
        unauthenticated,
        health,
        username: credentials.username.trim(),
        password: credentials.password,
        deviceName: deviceName,
        deviceKey: deviceKey,
      );
      final sessionToken = login['session_token'];
      if (sessionToken is! String || sessionToken.isEmpty) {
        return ConnectionResult.unreachable;
      }
      return await _activateSession(operation, uri, origin, sessionToken);
    } on ApiException catch (error) {
      if (operation != _operation) return ConnectionResult.unreachable;
      return error.statusCode == 401
          ? ConnectionResult.unauthorized
          : ConnectionResult.unreachable;
    } on Object {
      return ConnectionResult.unreachable;
    } finally {
      unauthenticated.close();
    }
  }

  @override
  /// 探测并恢复已保存 token；只有探测和再次持久化都成功才替换活动会话。
  Future<ConnectionResult> restore(String address, String sessionToken) async {
    final operation = ++_operation;
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    return _activateSession(operation, uri, normalizeOrigin(uri), sessionToken);
  }

  Future<ConnectionResult> _activateSession(
    int operation,
    Uri uri,
    String origin,
    String sessionToken,
  ) async {
    final candidate = ApiSession(origin: origin, token: sessionToken);
    final probe = _client.isolatedFor(candidate);
    var activated = false;
    try {
      final system = _systemDecoder.decode(await probe.getSystemInfo());
      final sources = await ApiSourceRepository(probe).list(refresh: true);
      final alias = await _aliasStore.read(origin);
      if (operation != _operation) return ConnectionResult.unreachable;
      final profile = ServerProfile(
        name: alias?.trim().isNotEmpty == true ? alias!.trim() : uri.host,
        address: origin,
        token: sessionToken,
        hostName: uri.host,
        sourceCount: sources.length,
        version: system.version,
        platform: system.platform,
        architecture: system.architecture,
        database: system.database,
        userRole: system.userRole,
        capabilities: system.capabilities,
      );
      final persisted = await _enqueueCredentialActivation(
        operation,
        StoredCredentials(origin: origin, sessionToken: sessionToken),
      );
      if (!persisted || operation != _operation) {
        return ConnectionResult.unreachable;
      }

      _apiSession.update(origin: origin, token: sessionToken);
      if (_sourceRepository case SessionSeedableSourceRepository cache) {
        cache.seedSessionCache(sources);
      }
      connectedProfile = profile;
      activated = true;
      return ConnectionResult.success;
    } on ApiException catch (error) {
      return operation == _operation && error.statusCode == 401
          ? ConnectionResult.unauthorized
          : ConnectionResult.unreachable;
    } on Object {
      return ConnectionResult.unreachable;
    } finally {
      if (!activated) await _bestEffortLogout(probe);
      probe.close();
    }
  }

  @override
  /// 同步清除内存会话后异步撤销旧 token；旧流程不会影响随后建立的新会话。
  /// 安全凭据清理失败会抛出，但网络登出失败或超时不会阻塞本地断开。
  Future<void> disconnect() async {
    _operation++;
    final previous = ApiSession(
      origin: _apiSession.origin,
      token: _apiSession.token,
    );
    connectedProfile = null;
    _apiSession.clear();
    final clearCredentials = _enqueueCredential(_credentialStore.clear);
    final logout = previous.token == null || previous.token!.isEmpty
        ? Future<void>.value()
        : _logoutIsolated(previous);
    await Future.wait([clearCredentials, logout]);
  }

  Future<bool> _enqueueCredentialActivation(
    int operation,
    StoredCredentials credentials,
  ) async {
    var persisted = false;
    await _enqueueCredential(() async {
      if (operation != _operation) return;
      await _credentialStore.write(credentials);
      persisted = operation == _operation;
    });
    return persisted;
  }

  Future<void> _enqueueCredential(Future<void> Function() action) {
    final next = _credentialQueue
        .catchError((_) {})
        .then<void>((_) => action());
    _credentialQueue = next.catchError((_) {});
    return next;
  }

  Future<Map<String, dynamic>> _loginCompatible(
    ApiClient client,
    Map<String, dynamic> health, {
    required String username,
    required String password,
    required String deviceName,
    required String deviceKey,
  }) async {
    final support = _deviceKeySupport(health);
    if (support == false) {
      return client.login(username, password, deviceName: deviceName);
    }
    try {
      return await client.login(
        username,
        password,
        deviceName: deviceName,
        deviceKey: deviceKey,
      );
    } on ApiException catch (error) {
      if (support == null && _isUnknownDeviceKey(error)) {
        return client.login(username, password, deviceName: deviceName);
      }
      rethrow;
    }
  }

  bool? _deviceKeySupport(Map<String, dynamic> health) {
    final direct = health['supports_device_key'];
    if (direct is bool) return direct;

    final apiVersion = health['api_version'];
    if (apiVersion is int) return apiVersion >= 2;

    final capabilities = health['capabilities'];
    if (capabilities is Map) {
      final declared = capabilities['auth.device_key'];
      if (declared is bool) return declared;
    }
    if (capabilities is List) {
      return capabilities.whereType<String>().contains('auth.device_key');
    }
    // 普通版本号没有稳定的功能分界，不能仅凭其高低安全地省略字段。
    return null;
  }

  bool _isUnknownDeviceKey(ApiException error) {
    if (error.statusCode != 400 || error.code != 'INVALID_REQUEST') {
      return false;
    }
    final message = error.message.toLowerCase();
    return message.contains('unknown field') && message.contains('device_key');
  }

  Future<void> _logoutIsolated(ApiSession session) async {
    final client = _client.isolatedFor(session);
    try {
      await _bestEffortLogout(client);
    } finally {
      client.close();
    }
  }

  Future<void> _bestEffortLogout(ApiClient client) async {
    try {
      await client.logout().timeout(_logoutTimeout);
    } on Object {
      // 候选放弃或本地断开不能被网络和旧服务端阻塞。
    }
  }

  /// 规范化服务 origin，保留反向代理路径并去掉尾部斜杠和查询参数。
  static String normalizeOrigin(Uri uri) {
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final path = segments.isEmpty ? '' : '/${segments.join('/')}';
    final normalized = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }
}
