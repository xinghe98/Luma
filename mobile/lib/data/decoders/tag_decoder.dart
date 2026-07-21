// Decodes tag list and mutation responses.
import '../models/api_tag.dart';
import 'decoder_utils.dart';

final class TagDecoder {
  const TagDecoder();

  Tag decode(Map<String, dynamic> json) {
    return Tag(
      id: requiredValue(json, 'id'),
      name: requiredValue(json, 'name'),
      usageCount: requiredValue(json, 'usage_count'),
      revision: requiredValue(json, 'revision'),
      createdAt: requiredDate(json, 'created_at'),
      updatedAt: requiredDate(json, 'updated_at'),
    );
  }

  List<Tag> decodeList(Map<String, dynamic> json) => listValue(
    json,
    'items',
  ).map((item) => decode(objectValue(item, 'tag'))).toList(growable: false);
}
