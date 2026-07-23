// Validates a server, activates its session, and persists credentials.
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

final class ApiConnectionService implements ConnectionService {
  ApiConnectionService({
    required ApiClient client,
    required ApiSession apiSession,
    required CredentialStore credentialStore,
    required ServerAliasStore aliasStore,
    SourceRepository? sourceRepository,
  }) : _client = client,
       _apiSession = apiSession,
       _credentialStore = credentialStore,
       _aliasStore = aliasStore,
       _sourceRepository = sourceRepository;

  final ApiClient _client;
  final ApiSession _apiSession;
  final CredentialStore _credentialStore;
  final ServerAliasStore _aliasStore;
  final SourceRepository? _sourceRepository;
  final SystemInfoDecoder _systemDecoder = const SystemInfoDecoder();
  int _operation = 0;
  Future<void> _credentialQueue = Future<void>.value();

  @override
  ServerProfile? connectedProfile;

  @override
  /// Verifies both public health and authenticated API access before saving.
  Future<ConnectionResult> test(String address, String token) async {
    final operation = ++_operation;
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    if (token.trim().isEmpty) return ConnectionResult.unauthorized;

    final origin = normalizeOrigin(uri);
    final candidate = ApiSession(origin: origin, token: token.trim());
    final probe = _client.isolatedFor(candidate);
    try {
      await probe.getHealth();
      final system = _systemDecoder.decode(await probe.getSystemInfo());
      final sources = await ApiSourceRepository(probe).list(refresh: true);
      final alias = await _aliasStore.read(origin);
      final profile = ServerProfile(
        name: alias?.trim().isNotEmpty == true ? alias!.trim() : uri.host,
        address: origin,
        token: token.trim(),
        hostName: uri.host,
        sourceCount: sources.length,
        version: system.version,
        platform: system.platform,
        architecture: system.architecture,
        database: system.database,
        userRole: system.userRole,
        capabilities: system.capabilities,
      );
      if (operation != _operation) return ConnectionResult.unreachable;
      _apiSession.update(origin: origin, token: token.trim());
      if (_sourceRepository case SessionSeedableSourceRepository cache) {
        cache.seedSessionCache(sources);
      }
      connectedProfile = profile;
      await _enqueueCredentialWrite(
        operation,
        StoredCredentials(origin: origin, token: token.trim()),
      );
      if (operation != _operation) return ConnectionResult.unreachable;
      return ConnectionResult.success;
    } on ApiException catch (error) {
      if (operation != _operation) return ConnectionResult.unreachable;
      return error.statusCode == 401
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
    final next = _credentialQueue.catchError((_) {}).then<void>((_) => action());
    // Keep the serialization chain usable after a storage failure while still
    // returning that failure to the operation that triggered it.
    _credentialQueue = next.catchError((_) {});
    return next;
  }

  /// Keeps non-root path prefixes (e.g. `/luma`) and only strips trailing slash.
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
