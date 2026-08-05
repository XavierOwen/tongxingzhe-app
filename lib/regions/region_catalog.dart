import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local_database.dart';
import 'region_models.dart';

/// 保存并验证全 App 共用的严格区域树。
final class RegionCatalog {
  const RegionCatalog(this._database);

  final LocalDatabase _database;

  /// 验证整棵快照后按父级在前的顺序写入，防止部分树落库。
  Future<void> installSnapshot(CanonicalRegionSnapshot snapshot) async {
    final ordered = _validatedParentFirst(snapshot);
    await _database.transaction(() async {
      for (final node in ordered) {
        await _database
            .into(_database.dbCanonicalRegionVersions)
            .insertOnConflictUpdate(
              DbCanonicalRegionVersionsCompanion.insert(
                regionVersionKey: versionKey(snapshot.version, node.regionId),
                regionId: node.regionId,
                treeVersion: snapshot.version,
                parentRegionVersionKey: Value(
                  node.parentRegionId == null
                      ? null
                      : versionKey(snapshot.version, node.parentRegionId!),
                ),
                canonicalName: node.canonicalName,
                kind: node.kind.storageValue,
                attributesJson: jsonEncode(node.attributes.toList()..sort()),
              ),
            );
      }
    });
  }

  /// 从最小节点沿唯一父键向上读取；第一项始终是传入节点。
  Future<List<CanonicalRegionNode>> ancestorPath({
    required String regionId,
    required String treeVersion,
  }) async {
    final result = <CanonicalRegionNode>[];
    var key = versionKey(treeVersion, regionId);
    final seen = <String>{};
    while (true) {
      if (!seen.add(key)) {
        throw const RegionCatalogException('region_tree_cycle');
      }
      final query = _database.select(_database.dbCanonicalRegionVersions)
        ..where((row) => row.regionVersionKey.equals(key));
      final row = await query.getSingleOrNull();
      if (row == null) {
        throw const RegionCatalogException('region_not_found');
      }
      final decoded = jsonDecode(row.attributesJson);
      if (decoded is! List<Object?> ||
          decoded.any((value) => value is! String)) {
        throw const RegionCatalogException('region_attributes_invalid');
      }
      result.add(
        CanonicalRegionNode(
          regionId: row.regionId,
          parentRegionId: row.parentRegionVersionKey == null
              ? null
              : _regionIdFromKey(row.parentRegionVersionKey!),
          canonicalName: row.canonicalName,
          kind: RegionKind.fromStorage(row.kind),
          attributes: decoded.cast<String>().toSet(),
        ),
      );
      final parent = row.parentRegionVersionKey;
      if (parent == null) {
        return List.unmodifiable(result);
      }
      key = parent;
    }
  }

  /// 已解析线下地点必须存在，而且父链中至少包含城市。
  Future<void> requireAnalyzableRegion({
    required String regionId,
    required String treeVersion,
  }) async {
    List<CanonicalRegionNode> path;
    try {
      path = await ancestorPath(regionId: regionId, treeVersion: treeVersion);
    } on RegionCatalogException {
      throw const RegionCatalogException('resolved_region_unknown');
    }
    if (!path.any((node) => node.kind == RegionKind.city)) {
      throw const RegionCatalogException('resolved_region_missing_city');
    }
  }

  Future<void> assignContact({
    required String contactId,
    required String regionId,
    required String treeVersion,
  }) async {
    await _database
        .into(_database.dbContactRegionAssignments)
        .insertOnConflictUpdate(
          DbContactRegionAssignmentsCompanion.insert(
            contactId: contactId,
            regionVersionKey: versionKey(treeVersion, regionId),
          ),
        );
  }

  Future<void> assignDraft({
    required String draftId,
    required String regionId,
    required String treeVersion,
  }) async {
    await _database
        .into(_database.dbDraftRegionAssignments)
        .insertOnConflictUpdate(
          DbDraftRegionAssignmentsCompanion.insert(
            draftId: draftId,
            regionVersionKey: versionKey(treeVersion, regionId),
          ),
        );
  }

  Future<void> clearDraftAssignment(String draftId) async {
    await (_database.delete(
      _database.dbDraftRegionAssignments,
    )..where((row) => row.draftId.equals(draftId))).go();
  }

  static String versionKey(String version, String regionId) =>
      '${Uri.encodeComponent(version)}::${Uri.encodeComponent(regionId)}';

  List<CanonicalRegionNode> _validatedParentFirst(
    CanonicalRegionSnapshot snapshot,
  ) {
    if (snapshot.version.trim().isEmpty || snapshot.nodes.isEmpty) {
      throw const RegionCatalogException('region_snapshot_empty');
    }
    final byId = <String, CanonicalRegionNode>{};
    for (final node in snapshot.nodes) {
      if (node.regionId.trim().isEmpty ||
          node.canonicalName.trim().isEmpty ||
          node.attributes.any((value) => value.trim().isEmpty)) {
        throw const RegionCatalogException('region_node_invalid');
      }
      if (byId[node.regionId] != null) {
        throw const RegionCatalogException('region_id_duplicate');
      }
      byId[node.regionId] = node;
    }
    for (final node in snapshot.nodes) {
      final parent = node.parentRegionId;
      if (parent != null &&
          (parent == node.regionId || !byId.containsKey(parent))) {
        throw const RegionCatalogException('region_parent_invalid');
      }
    }

    final ordered = <CanonicalRegionNode>[];
    final visiting = <String>{};
    final visited = <String>{};
    void visit(CanonicalRegionNode node) {
      if (visited.contains(node.regionId)) {
        return;
      }
      if (!visiting.add(node.regionId)) {
        throw const RegionCatalogException('region_tree_cycle');
      }
      final parentId = node.parentRegionId;
      if (parentId != null) {
        visit(byId[parentId]!);
      }
      visiting.remove(node.regionId);
      visited.add(node.regionId);
      ordered.add(node);
    }

    for (final node in snapshot.nodes) {
      visit(node);
    }
    return ordered;
  }

  String _regionIdFromKey(String key) {
    final separator = key.indexOf('::');
    if (separator < 0) {
      throw const RegionCatalogException('region_key_invalid');
    }
    return Uri.decodeComponent(key.substring(separator + 2));
  }
}
