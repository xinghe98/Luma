import '../models/server_profile.dart';

enum ConnectionResult { success, invalidAddress, unauthorized, unreachable }

/// LoginCredentials 只在一次登录请求期间保存用户名和密码。
final class LoginCredentials {
  const LoginCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

abstract interface class ConnectionService {
  ServerProfile? get connectedProfile;

  /// 使用账号密码登录并激活新会话，不会持久化 password。
  Future<ConnectionResult> login(String address, LoginCredentials credentials);

  /// 恢复之前安全保存的会话；失效时返回 unauthorized。
  Future<ConnectionResult> restore(String address, String sessionToken);

  Future<void> disconnect();
}
