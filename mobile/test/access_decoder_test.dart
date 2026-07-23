import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/decoders/access_decoder.dart';

void main() {
  const decoder = AccessDecoder();

  test('decodes required access user values', () {
    final user = decoder.decodeUser(_userJson());

    expect(user.id, 'user-1');
    expect(user.name, 'Administrator');
    expect(user.role, 'admin');
    expect(user.enabled, isTrue);
    expect(user.createdAt, DateTime.utc(2026, 7, 1, 12));
    expect(user.updatedAt, DateTime.utc(2026, 7, 2, 12));
    expect(user.isAdmin, isTrue);
  });

  test('rejects an access user missing a required value', () {
    final json = _userJson()..remove('enabled');

    expect(() => decoder.decodeUser(json), throwsA(isA<FormatException>()));
  });

  test('decodes nullable access token dates', () {
    final token = decoder.decodeToken(_tokenJson());

    expect(token.id, 'token-1');
    expect(token.userId, 'user-1');
    expect(token.tokenPrefix, 'luma_abc');
    expect(token.expiresAt, isNull);
    expect(token.revokedAt, isNull);
    expect(token.isRevoked, isFalse);
  });

  test('decodes an issued token plaintext value and metadata', () {
    final issued = decoder.decodeIssuedToken({
      ..._tokenJson(expiresAt: '2026-08-01T00:00:00Z'),
      'token': 'one-time-plaintext-token',
    });

    expect(issued.id, 'token-1');
    expect(issued.userId, 'user-1');
    expect(issued.expiresAt, DateTime.utc(2026, 8, 1));
    expect(issued.token, 'one-time-plaintext-token');
  });

  test('decodes user and token lists plus granted source IDs', () {
    final users = decoder.decodeUserList({
      'items': [
        _userJson(),
        {..._userJson(), 'id': 'user-2'},
      ],
    });
    final tokens = decoder.decodeTokenList({
      'items': [
        _tokenJson(),
        {..._tokenJson(), 'id': 'token-2'},
      ],
    });
    final grants = decoder.decodeGrantIds({
      'source_ids': ['source-1', 'source-2'],
    });

    expect(users.map((user) => user.id), ['user-1', 'user-2']);
    expect(tokens.map((token) => token.id), ['token-1', 'token-2']);
    expect(grants, ['source-1', 'source-2']);
  });
}

Map<String, dynamic> _userJson() => {
  'id': 'user-1',
  'name': 'Administrator',
  'role': 'admin',
  'enabled': true,
  'created_at': '2026-07-01T12:00:00Z',
  'updated_at': '2026-07-02T12:00:00Z',
};

Map<String, dynamic> _tokenJson({String? expiresAt, String? revokedAt}) => {
  'id': 'token-1',
  'user_id': 'user-1',
  'name': 'Mobile',
  'token_prefix': 'luma_abc',
  'expires_at': expiresAt,
  'revoked_at': revokedAt,
  'created_at': '2026-07-03T12:00:00Z',
};
