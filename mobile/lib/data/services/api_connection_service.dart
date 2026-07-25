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
import 'device_name_resolver.dart';

final class ApiConnectionService implements ConnectionService {
  ApiConnectionService({
    required ApiClient client,
    required ApiSession apiSession,
    required CredentialStore credentialStore,
    required ServerAliasStore aliasStore,
    SourceRepository? sourceRepository,
    DeviceNameResolver? deviceNameResolver,
  }) : _client = client,
       _apiSession = apiSession,
       _credentialStore = credentialStore,
       _aliasStore = aliasStore,
       _sourceRepository = sourceRepository,
       _deviceNameResolver = deviceNameResolver ?? PlatformDeviceNameResolver();

  final ApiClient _client;
  final ApiSession _apiSession;
  final CredentialStore _credentialStore;
  final ServerAliasStore _aliasStore;
  final SourceRepository? _sourceRepository;
  final DeviceNameResolver _deviceNameResolver;
  final SystemInfoDecoder _systemDecoder = const SystemInfoDecoder();
  int _operation = 0;
  Future<void> _credentialQueue = Future<void>.value();

  @override
  ServerProfile? connectedProfile;

  @override
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
      if (operation != _operation) return ConnectionResult.unreachable;
      await unauthenticated.getHealth();
      final login = await unauthenticated.login(
        credentials.username.trim(),
        credentials.password,
        deviceName: deviceName,
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
  Future<ConnectionResult> restore(String address, String sessionToken) async {
    final operation = ++_operation;
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
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
      _apiSession.update(origin: origin, token: sessionToken);
      if (_sourceRepository case SessionSeedableSourceRepository cache) {
        cache.seedSessionCache(sources);
      }
      connectedProfile = profile;
      await _enqueueCredentialWrite(
        operation,
        StoredCredentials(origin: origin, sessionToken: sessionToken),
      );
      return operation == _operation
          ? ConnectionResult.success
          : ConnectionResult.unreachable;
    } on ApiException catch (error) {
      return operation == _operation && error.statusCode == 401
          ? ConnectionResult.unauthorized
          : ConnectionResult.unreachable;
    } on Object {
      return ConnectionResult.unreachable;
    } finally {
      probe.close();
    }
  }

  @override
  Future<void> disconnect() async {
    final operation = ++_operation;
    connectedProfile = null;
    _apiSession.clear();
    await _enqueueCredential(() async {
      if (operation != _operation) return;
      await _credentialStore.clear();
    });
  }

  Future<void> _enqueueCredentialWrite(
    int operation,
    StoredCredentials credentials,
  ) => _enqueueCredential(() async {
    if (operation != _operation) return;
    await _credentialStore.write(credentials);
  });

  Future<void> _enqueueCredential(Future<void> Function() action) {
    final next = _credentialQueue
        .catchError((_) {})
        .then<void>((_) => action());
    _credentialQueue = next.catchError((_) {});
    return next;
  }

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
