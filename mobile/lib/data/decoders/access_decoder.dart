// Strictly decodes administrator access-control payloads.
import '../models/api_access.dart';
import 'decoder_utils.dart';

final class AccessDecoder {
  const AccessDecoder();

  AccessUser decodeUser(Map<String, dynamic> json) => AccessUser(
    id: requiredValue(json, 'id'),
    name: requiredValue(json, 'name'),
    role: requiredValue(json, 'role'),
    enabled: requiredValue(json, 'enabled'),
    createdAt: requiredDate(json, 'created_at'),
    updatedAt: requiredDate(json, 'updated_at'),
  );

  AccessToken decodeToken(Map<String, dynamic> json) => AccessToken(
    id: requiredValue(json, 'id'),
    userId: requiredValue(json, 'user_id'),
    name: requiredValue(json, 'name'),
    tokenPrefix: requiredValue(json, 'token_prefix'),
    expiresAt: nullableDate(json, 'expires_at'),
    revokedAt: nullableDate(json, 'revoked_at'),
    createdAt: requiredDate(json, 'created_at'),
  );

  IssuedAccessToken decodeIssuedToken(Map<String, dynamic> json) {
    final metadata = decodeToken(json);
    return IssuedAccessToken(
      id: metadata.id,
      userId: metadata.userId,
      name: metadata.name,
      tokenPrefix: metadata.tokenPrefix,
      expiresAt: metadata.expiresAt,
      revokedAt: metadata.revokedAt,
      createdAt: metadata.createdAt,
      token: requiredValue(json, 'token'),
    );
  }

  List<AccessUser> decodeUserList(Map<String, dynamic> json) =>
      listValue(json, 'items')
          .map((value) => decodeUser(objectValue(value, 'access user')))
          .toList(growable: false);

  List<AccessToken> decodeTokenList(Map<String, dynamic> json) =>
      listValue(json, 'items')
          .map((value) => decodeToken(objectValue(value, 'access token')))
          .toList(growable: false);

  List<String> decodeGrantIds(Map<String, dynamic> json) =>
      listValue(json, 'source_ids')
          .map((value) {
            if (value is String) return value;
            throw FormatException('Expected source_ids item to be String');
          })
          .toList(growable: false);
}
