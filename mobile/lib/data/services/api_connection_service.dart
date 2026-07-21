// Validates a server, activates its session, and persists credentials.
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/api_session.dart';
import '../decoders/system_info_decoder.dart';
import '../models/server_profile.dart';
import '../repositories/source_repository.dart';
import '../storage/credential_store.dart';
import '../storage/server_alias_store.dart';
import 'connection_service.dart';

final class ApiConnectionService implements ConnectionService {
  ApiConnectionService({
    required ApiClient client,
    required ApiSession apiSession,
    required CredentialStore credentialStore,
    required SourceRepository sourceRepository,
    required ServerAliasStore aliasStore,
  }) : _client = client,
       _apiSession = apiSession,
       _credentialStore = credentialStore,
       _sourceRepository = sourceRepository,
       _aliasStore = aliasStore;

  final ApiClient _client;
  final ApiSession _apiSession;
  final CredentialStore _credentialStore;
  final SourceRepository _sourceRepository;
  final ServerAliasStore _aliasStore;
  final SystemInfoDecoder _systemDecoder = const SystemInfoDecoder();

  @override
  ServerProfile? connectedProfile;

  @override
  /// Verifies both public health and authenticated API access before saving.
  Future<ConnectionResult> test(String address, String token) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    if (token.trim().isEmpty) return ConnectionResult.unauthorized;

    final previousOrigin = _apiSession.origin;
    final previousToken = _apiSession.token;
    final origin = normalizeOrigin(uri);
    _apiSession.update(origin: origin, token: token.trim());
    try {
      await _client.getHealth();
      final system = _systemDecoder.decode(await _client.getSystemInfo());
      final sources = await _sourceRepository.list(refresh: true);
      final alias = await _aliasStore.read(_apiSession.origin);
      connectedProfile = ServerProfile(
        name: alias?.trim().isNotEmpty == true ? alias!.trim() : uri.host,
        address: _apiSession.origin,
        token: token.trim(),
        hostName: uri.host,
        sourceCount: sources.length,
        version: system.version,
        platform: system.platform,
        architecture: system.architecture,
        database: system.database,
      );
      await _credentialStore.write(
        StoredCredentials(origin: _apiSession.origin, token: token.trim()),
      );
      return ConnectionResult.success;
    } on ApiException catch (error) {
      _apiSession.update(origin: previousOrigin, token: previousToken);
      return error.statusCode == 401
          ? ConnectionResult.unauthorized
          : ConnectionResult.unreachable;
    } on Object {
      _apiSession.update(origin: previousOrigin, token: previousToken);
      return ConnectionResult.unreachable;
    }
  }

  @override
  Future<void> disconnect() async {
    connectedProfile = null;
    _apiSession.clear();
    await _credentialStore.clear();
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
