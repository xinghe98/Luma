// Decodes revision-controlled per-media user data.
import '../models/api_user_data.dart';
import 'decoder_utils.dart';
import 'tag_decoder.dart';

final class MediaUserDataDecoder {
  const MediaUserDataDecoder({this.tagDecoder = const TagDecoder()});

  final TagDecoder tagDecoder;

  MediaUserData decode(Map<String, dynamic> json) {
    return MediaUserData(
      mediaId: requiredValue(json, 'media_id'),
      customTitle: nullableValue(json, 'custom_title'),
      favorite: requiredValue(json, 'favorite'),
      notes: nullableValue(json, 'notes'),
      progressMs: requiredValue(json, 'progress_ms'),
      completed: requiredValue(json, 'completed'),
      lastPlayedAt: nullableDate(json, 'last_played_at'),
      tags: listValue(json, 'tags')
          .map((item) => tagDecoder.decode(objectValue(item, 'tag')))
          .toList(growable: false),
      revision: requiredValue(json, 'revision'),
      createdAt: nullableDate(json, 'created_at'),
      updatedAt: nullableDate(json, 'updated_at'),
    );
  }
}
