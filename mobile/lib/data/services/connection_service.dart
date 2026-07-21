import '../models/server_profile.dart';

enum ConnectionResult { success, invalidAddress, unauthorized, unreachable }

abstract interface class ConnectionService {
  ServerProfile? get connectedProfile;

  Future<ConnectionResult> test(String address, String token);

  Future<void> disconnect();
}
