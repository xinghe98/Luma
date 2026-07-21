import 'package:flutter/foundation.dart';

import 'app_destination.dart';

class ShellController extends ChangeNotifier {
  AppDestination _selected = AppDestination.home;

  AppDestination get selected => _selected;

  void select(AppDestination destination) {
    if (_selected == destination) return;
    _selected = destination;
    notifyListeners();
  }
}
