// Decodes authenticated server information.
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
    );
  }
}
