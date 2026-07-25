import '../models/api_system_info.dart';
import 'decoder_utils.dart';

final class SystemInfoDecoder {
  const SystemInfoDecoder();

  SystemInfo decode(Map<String, dynamic> json) {
    return SystemInfo(
      version: requiredValue(json, 'version'),
      platform: requiredValue(json, 'platform'),
      architecture: requiredValue(json, 'architecture'),
      database: requiredValue(json, 'database'),
      userRole:
          (json['user'] as Map<String, dynamic>?)?['role'] as String? ??
          'admin',
      capabilities: (json['capabilities'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
