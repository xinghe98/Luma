import 'dart:math';

final Random _random = Random.secure();

String newAccessRequestId() => List<String>.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
