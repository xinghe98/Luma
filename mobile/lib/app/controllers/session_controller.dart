import 'package:flutter/foundation.dart';

import '../../data/models/server_profile.dart';

class SessionController extends ChangeNotifier {
  ServerProfile? _server;

  ServerProfile? get server => _server;
  bool get isConnected => _server != null;

  void connect(ServerProfile server) {
    _server = server;
    notifyListeners();
  }

  void disconnect() {
    _server = null;
    notifyListeners();
  }

  void rename(String name) {
    final server = _server;
    if (server == null) return;
    _server = server.copyWith(name: name);
    notifyListeners();
  }
}
