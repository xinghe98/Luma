import '../models/server_profile.dart';
import '../services/connection_service.dart';

class MockConnectionService implements ConnectionService {
  @override
  ServerProfile? connectedProfile;

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
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
    if (uri.host.contains('offline')) return ConnectionResult.unreachable;
    connectedProfile = ServerProfile(
      name: '家庭影音服务器',
      address: address.trim(),
      token: 'mock-session',
      hostName: uri.host,
      sourceCount: 3,
      version: 'dev',
      platform: 'windows',
      architecture: 'amd64',
      database: 'ok',
    );
    return ConnectionResult.success;
  }

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) =>
      login(
        address,
        const LoginCredentials(username: 'mock', password: 'mock'),
      );

  @override
  Future<void> disconnect() async => connectedProfile = null;
}
