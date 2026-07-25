part of '../api_client.dart';

mixin _CatalogEndpoints on _ApiTransport {
  Future<Map<String, dynamic>> getCatalog({String? kind, String? query}) =>
      _json(
        'GET',
        _api('/catalog'),
        queryParameters: {'kind': ?kind, 'q': ?query},
      );

  Future<Map<String, dynamic>> getCatalogDetail(String id) =>
      _json('GET', _api('/catalog/${_segment(id)}'));

  Future<Map<String, dynamic>> getCatalogIssues() =>
      _json('GET', _api('/catalog/issues'));

  Future<void> updateCatalogMatch(
    String mediaId,
    Map<String, dynamic> data,
  ) async {
    await _empty(
      'PATCH',
      _api('/catalog/media/${_segment(mediaId)}'),
      data: data,
    );
  }

}
