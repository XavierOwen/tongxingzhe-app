import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/local_database.dart';
import '../features/contact_journal/contact_models.dart';
import '../identity/identity_session.dart';
import 'region_catalog.dart';
import 'region_models.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

/// 把 [PendingContactLocation] 中的合法坐标匹配到平台发布的规范区域树。
///
/// 正式 Adapter 自行取得 access token、调用 HTTPS Backend，并在本地原子安装
/// 返回的区域父链。成功时返回 [ResolvedContactLocation]。未配置 Backend、
/// 断网、身份失效、响应无效或没有边界命中时，返回原来的待解析地点。
/// 调用者不传业务用户或权限；解析失败不能丢弃坐标，也不能改写成 `N/A`。
abstract interface class ContactRegionResolver {
  Future<ContactLocation> resolve(PendingContactLocation location);

  Future<void> close();
}

/// 没有 Backend 配置时保留明确的待解析状态。
final class DeferredContactRegionResolver implements ContactRegionResolver {
  const DeferredContactRegionResolver();

  @override
  Future<ContactLocation> resolve(PendingContactLocation location) async =>
      location;

  @override
  Future<void> close() async {}
}

ContactRegionResolver productionContactRegionResolver(
  IdentitySession identitySession,
  LocalDatabase database,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredContactRegionResolver();
  }
  return HttpContactRegionResolver(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    regionCatalog: RegionCatalog(database),
    client: http.Client(),
  );
}

/// 调用自有 Backend，并在返回地点前原子安装其规范父链。
final class HttpContactRegionResolver implements ContactRegionResolver {
  factory HttpContactRegionResolver({
    required Uri baseUri,
    required IdentitySession identitySession,
    required RegionCatalog regionCatalog,
    required http.Client client,
    Duration timeout = const Duration(seconds: 10),
  }) => HttpContactRegionResolver._(
    _validatedBaseUri(baseUri),
    identitySession,
    regionCatalog,
    client,
    timeout,
  );

  HttpContactRegionResolver._(
    this._baseUri,
    this._identitySession,
    this._regionCatalog,
    this._client,
    this._timeout,
  );

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final RegionCatalog _regionCatalog;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<ContactLocation> resolve(PendingContactLocation location) async {
    try {
      var tokenResult = await _identitySession.accessToken();
      if (tokenResult is! IdentitySuccess<IdentityAccessToken>) {
        return location;
      }
      var response = await _send(location, tokenResult.value);
      if (response.statusCode == 401) {
        tokenResult = await _identitySession.accessToken(forceRefresh: true);
        if (tokenResult is! IdentitySuccess<IdentityAccessToken>) {
          return location;
        }
        response = await _send(location, tokenResult.value);
      }
      if (response.statusCode == 202) {
        return location;
      }
      if (response.statusCode != 200) {
        return location;
      }
      return await _parseResolved(response.body, location);
    } on TimeoutException {
      return location;
    } on http.ClientException {
      return location;
    } on FormatException {
      return location;
    } on RegionCatalogException {
      return location;
    }
  }

  Future<http.Response> _send(
    PendingContactLocation location,
    IdentityAccessToken token,
  ) {
    return _client
        .post(
          _baseUri.resolve('/v1/regions/resolve'),
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer ${token.value}',
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'latitude': location.latitude,
            'longitude': location.longitude,
          }),
        )
        .timeout(_timeout);
  }

  Future<ResolvedContactLocation> _parseResolved(
    String responseBody,
    PendingContactLocation locationSource,
  ) async {
    final root = _object(jsonDecode(responseBody), 'response');
    if (root['result'] != 'resolved') {
      throw const FormatException('region result must be resolved');
    }
    final location = _object(root['location'], 'location');
    final tree = _object(root['region_tree'], 'region_tree');
    final version = _nonEmptyString(tree['version'], 'region tree version');
    final contentFingerprint = _sha256Fingerprint(
      tree['content_fingerprint'],
      'region tree content fingerprint',
    );
    final resolverContractVersion = _nonEmptyString(
      tree['resolver_contract_version'],
      'resolver contract version',
    );
    if (resolverContractVersion != 'canonical-region-resolution:v1') {
      throw const FormatException('resolver contract version is unsupported');
    }
    final nodeValues = tree['nodes'];
    if (nodeValues is! List<Object?> || nodeValues.isEmpty) {
      throw const FormatException('region tree nodes must be a non-empty list');
    }
    final nodes = [for (final value in nodeValues) _node(value)];
    final regionId = _nonEmptyString(
      location['smallest_region_id'],
      'smallest region ID',
    );
    final responseVersion = _nonEmptyString(
      location['region_tree_version'],
      'location region tree version',
    );
    if (location['kind'] != 'resolved' ||
        responseVersion != version ||
        nodes.last.regionId != regionId) {
      throw const FormatException('resolved region response is inconsistent');
    }
    await _regionCatalog.installSnapshot(
      CanonicalRegionSnapshot(version: version, nodes: nodes),
    );
    await _regionCatalog.requireAnalyzableRegion(
      regionId: regionId,
      treeVersion: version,
    );
    return ResolvedContactLocation(
      placeName: _nonEmptyString(location['place_name'], 'place name'),
      smallestRegionId: regionId,
      regionTreeVersion: version,
      source: CapturedCoordinatesLocationSource(
        latitude: locationSource.latitude,
        longitude: locationSource.longitude,
        accuracyMeters: locationSource.accuracyMeters,
        resolverContractVersion: resolverContractVersion,
        regionTreeContentFingerprint: contentFingerprint,
      ),
    );
  }

  CanonicalRegionNode _node(Object? value) {
    final node = _object(value, 'region node');
    final parentValue = node['parent_region_id'];
    if (parentValue != null && parentValue is! String) {
      throw const FormatException('parent region ID must be a string');
    }
    final attributesValue = node['attributes'];
    if (attributesValue is! List<Object?> ||
        attributesValue.any((attribute) => attribute is! String)) {
      throw const FormatException('region attributes must be strings');
    }
    try {
      return CanonicalRegionNode(
        regionId: _nonEmptyString(node['region_id'], 'region ID'),
        parentRegionId: parentValue as String?,
        canonicalName: _nonEmptyString(
          node['canonical_name'],
          'canonical region name',
        ),
        kind: RegionKind.fromStorage(
          _nonEmptyString(node['kind'], 'region kind'),
        ),
        attributes: Set.unmodifiable(attributesValue.cast<String>()),
      );
    } on StateError {
      throw const FormatException('region kind is unsupported');
    }
  }

  @override
  Future<void> close() async => _client.close();
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _nonEmptyString(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$name must be a non-empty string');
  }
  return value;
}

String _sha256Fingerprint(Object? value, String name) {
  final fingerprint = _nonEmptyString(value, name);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
    throw FormatException('$name must be lowercase SHA-256');
  }
  return fingerprint;
}

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('BACKEND_BASE_URL must be an absolute URL');
  }
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'BACKEND_BASE_URL must use HTTPS except on localhost',
    );
  }
  return value;
}
