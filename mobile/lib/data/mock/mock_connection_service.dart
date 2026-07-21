import '../models/server_profile.dart';
import '../services/connection_service.dart';

class MockConnectionService implements ConnectionService {
  @override
  ServerProfile? connectedProfile;

  @override
  Future<ConnectionResult> test(String address, String token) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    if (uri.host.contains('offline')) return ConnectionResult.unreachable;
    connectedProfile = ServerProfile(
      name: '家庭影音服务器',
      address: address.trim(),
      token: token,
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
  Future<void> disconnect() async => connectedProfile = null;
}
