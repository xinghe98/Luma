import '../models/api_access.dart';
import 'decoder_utils.dart';

final class AccessDecoder {
  const AccessDecoder();

  AccessUser decodeUser(Map<String, dynamic> json) => AccessUser(
    id: requiredValue(json, 'id'),
    name: requiredValue(json, 'name'),
    username: requiredValue(json, 'username'),
    role: requiredValue(json, 'role'),
    enabled: requiredValue(json, 'enabled'),
    online: optionalValue<bool>(json, 'online') ?? false,
    createdAt: requiredDate(json, 'created_at'),
    updatedAt: requiredDate(json, 'updated_at'),
  );

  LoginSession decodeSession(Map<String, dynamic> json) => LoginSession(
    id: requiredValue(json, 'id'),
    userId: requiredValue(json, 'user_id'),
    name: requiredValue(json, 'name'),
    expiresAt: nullableDate(json, 'expires_at'),
    revokedAt: nullableDate(json, 'revoked_at'),
    createdAt: requiredDate(json, 'created_at'),
  );

  List<AccessUser> decodeUserList(Map<String, dynamic> json) =>
      listValue(json, 'items')
          .map((value) => decodeUser(objectValue(value, 'access user')))
          .toList(growable: false);

  List<LoginSession> decodeSessionList(Map<String, dynamic> json) =>
      listValue(json, 'items')
          .map((value) => decodeSession(objectValue(value, 'login session')))
          .toList(growable: false);

  List<String> decodeGrantIds(Map<String, dynamic> json) =>
      listValue(json, 'source_ids')
          .map((value) {
            if (value is String) return value;
            throw FormatException('Expected source_ids item to be String');
          })
          .toList(growable: false);
}
