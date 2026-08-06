/// 规范区域节点的稳定类型；属性不伪装成额外层级。
enum RegionKind {
  country('country'),
  adminArea('admin_area'),
  city('city'),
  district('district'),
  neighborhood('neighborhood'),
  street('street'),
  institution('institution'),
  venue('venue'),
  other('other');

  const RegionKind(this.storageValue);

  final String storageValue;

  static RegionKind fromStorage(String value) =>
      RegionKind.values.singleWhere((kind) => kind.storageValue == value);
}

/// 某一规范区域树版本中的单个节点。
final class CanonicalRegionNode {
  const CanonicalRegionNode({
    required this.regionId,
    this.parentRegionId,
    required this.canonicalName,
    required this.kind,
    this.attributes = const {},
  });

  final String regionId;
  final String? parentRegionId;
  final String canonicalName;
  final RegionKind kind;
  final Set<String> attributes;
}

/// 一次原子安装的规范区域树快照。
final class CanonicalRegionSnapshot {
  const CanonicalRegionSnapshot({required this.version, required this.nodes});

  final String version;
  final List<CanonicalRegionNode> nodes;
}

final class RegionCatalogException implements Exception {
  const RegionCatalogException(this.code);

  final String code;

  @override
  String toString() => 'RegionCatalogException($code)';
}
