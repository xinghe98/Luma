// Decodes the administrator-only media-root list returned by ApiClient for
// ApiSourceRepository; paths remain server-local and are never persisted here.
import 'decoder_utils.dart';

/// Converts the configured media-root response into validated path strings.
/// Throws [FormatException] when the server response does not contain strings.
final class MediaRootDecoder {
  const MediaRootDecoder();

  /// Decodes the response body returned by the media-root list endpoint.
  /// Every item must be a non-empty server-local path.
  List<String> decodeList(Map<String, dynamic> json) => List.unmodifiable([
    for (final value in listValue(json, 'items'))
      if (value is String && value.trim().isNotEmpty)
        value
      else
        throw FormatException('Expected items[] to be a non-empty string'),
  ]);
}
