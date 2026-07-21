// Decodes media source payloads.
import '../models/api_source.dart';
import 'decoder_utils.dart';

final class SourceDecoder {
  const SourceDecoder();

  Source decode(Map<String, dynamic> json) {
    return Source(
      id: requiredValue(json, 'id'),
      name: requiredValue(json, 'name'),
      type: requiredValue(json, 'type'),
      enabled: requiredValue(json, 'enabled'),
      status: requiredValue(json, 'status'),
      lastScanId: optionalValue(json, 'last_scan_id'),
      lastSeenAt: optionalDate(json, 'last_seen_at'),
      createdAt: requiredDate(json, 'created_at'),
      updatedAt: requiredDate(json, 'updated_at'),
    );
  }

  List<Source> decodeList(Map<String, dynamic> json) => listValue(
    json,
    'items',
  ).map((item) => decode(objectValue(item, 'source'))).toList(growable: false);
}
