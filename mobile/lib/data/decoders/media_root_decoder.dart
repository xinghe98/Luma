import 'decoder_utils.dart';

final class MediaRootDecoder {
  const MediaRootDecoder();

  List<String> decodeList(Map<String, dynamic> json) => List.unmodifiable([
    for (final value in listValue(json, 'items'))
      if (value is String && value.trim().isNotEmpty)
        value
      else
        throw FormatException('Expected items[] to be a non-empty string'),
  ]);
}
