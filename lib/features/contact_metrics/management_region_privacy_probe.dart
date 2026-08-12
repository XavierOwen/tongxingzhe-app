/// 私有区域报告候选的 fixture-first 披露风险探针。
///
/// 该模块不执行查询、不授权用户，也不生成生产报告。输入只用于 synthetic
/// 对账；输出只保留稳定身份、状态和 allowlist 原因码。
abstract final class ManagementRegionPrivacyProbeV1 {
  static const probeId = 'management_region_privacy_probe_v1';
  static const queryFingerprint = 'management-region-privacy-probe:v1';

  static ManagementRegionPrivacyAssessmentV1 assess(
    Map<String, Object?> probe,
  ) {
    try {
      _expectKeys(probe, const {
        'probe_id',
        'query_fingerprint',
        'view_mode',
        'tree_version',
        'region_granularity',
        'reports',
        'region_relationships',
        'query_overlaps',
        'version_mappings',
        'location_states',
        'external_facts',
      });
      if (_string(probe, 'probe_id') != probeId ||
          _string(probe, 'query_fingerprint') != queryFingerprint) {
        throw const FormatException('unknown probe identity');
      }
      final viewMode = _string(probe, 'view_mode');
      final treeVersion = _string(probe, 'tree_version');
      final regionGranularity = _string(probe, 'region_granularity');
      final reports = _list(probe, 'reports').map(_report).toList();
      if (reports.isEmpty) throw const FormatException('reports are empty');
      final relationships = _list(
        probe,
        'region_relationships',
      ).map(_relationship).toList();
      final queryOverlaps = _list(
        probe,
        'query_overlaps',
      ).map(_queryOverlap).toList();
      final mappings = _list(probe, 'version_mappings').map(_mapping).toList();
      final locations = _list(probe, 'location_states').map(_location).toList();
      final externalFacts = _list(
        probe,
        'external_facts',
      ).map(_externalFact).toList();

      if (reports.map((report) => report.reportKey).toSet().length !=
          reports.length) {
        throw const FormatException('duplicate report key');
      }
      for (final report in reports) {
        final coordinates = <(String, String, String)>{};
        for (final cell in report.cells) {
          if (!coordinates.add((
            cell.regionId,
            cell.treeVersion,
            cell.categoryKey,
          ))) {
            throw const FormatException('duplicate report cell');
          }
        }
      }
      final cells = <_ReportCell>[];
      for (
        var reportIndex = 0;
        reportIndex < reports.length;
        reportIndex += 1
      ) {
        final report = reports[reportIndex];
        for (final cell in report.cells) {
          cells.add((reportIndex: reportIndex, report: report, cell: cell));
        }
      }
      final reasons = <String>[];
      void block(bool condition, String reason) {
        if (condition) reasons.add(reason);
      }

      block(
        relationships.any(
          (relationship) => cells.any(
            (parent) =>
                parent.cell.regionId == relationship.parentRegionId &&
                parent.cell.treeVersion == relationship.treeVersion &&
                parent.cell.privacyStatus == 'displayed' &&
                cells.any(
                  (child) =>
                      child.report.periodKey == parent.report.periodKey &&
                      child.cell.regionId == relationship.childRegionId &&
                      child.cell.treeVersion == relationship.treeVersion &&
                      child.cell.privacyStatus == 'displayed',
                ),
          ),
        ),
        'parent_child_overlap',
      );
      block(
        queryOverlaps.any(
          (overlap) => cells.any(
            (left) =>
                left.cell.regionId == overlap.leftRegionId &&
                left.cell.treeVersion == overlap.leftTreeVersion &&
                left.cell.privacyStatus == 'displayed' &&
                cells.any(
                  (right) =>
                      right.report.periodKey == left.report.periodKey &&
                      right.cell.regionId == overlap.rightRegionId &&
                      right.cell.treeVersion == overlap.rightTreeVersion &&
                      right.cell.privacyStatus == 'displayed',
                ),
          ),
        ),
        'overlapping_query_sets',
      );
      block(
        mappings.any(
          (mapping) => cells.any(
            (source) =>
                source.cell.regionId == mapping.fromRegionId &&
                source.cell.treeVersion == mapping.fromTreeVersion &&
                cells.any(
                  (target) =>
                      target.report.periodKey == source.report.periodKey &&
                      target.cell.regionId == mapping.toRegionId &&
                      target.cell.treeVersion == mapping.toTreeVersion,
                ),
          ),
        ),
        'cross_version_overlap',
      );
      block(
        _anyCellPair(
          cells,
          (earlier, later) =>
              _sameCellCoordinate(earlier, later) &&
              earlier.cell.privacyStatus == 'displayed' &&
              later.cell.privacyStatus == 'displayed' &&
              earlier.cell.valueCount != later.cell.valueCount,
        ),
        'shared_period_value_changed',
      );
      block(
        _anyCellPair(
          cells,
          (earlier, later) =>
              _sameCellCoordinate(earlier, later) &&
              earlier.cell.privacyStatus != later.cell.privacyStatus,
        ),
        'shared_period_privacy_status_changed',
      );
      block(
        relationships.any(
              (relationship) => cells.any(
                (parent) =>
                    parent.cell.regionId == relationship.parentRegionId &&
                    parent.cell.treeVersion == relationship.treeVersion &&
                    parent.cell.privacyStatus == 'displayed' &&
                    cells.any(
                      (child) =>
                          child.report.periodKey == parent.report.periodKey &&
                          child.cell.regionId == relationship.childRegionId &&
                          child.cell.treeVersion == relationship.treeVersion &&
                          child.cell.privacyStatus == 'suppressed',
                    ),
              ),
            ) ||
            cells.any(
              (total) =>
                  total.cell.categoryKey == 'all' &&
                  total.cell.privacyStatus == 'displayed' &&
                  cells.any(
                    (category) =>
                        category.report.periodKey == total.report.periodKey &&
                        category.cell.regionId == total.cell.regionId &&
                        category.cell.treeVersion == total.cell.treeVersion &&
                        category.cell.categoryKey != 'all' &&
                        category.cell.privacyStatus == 'suppressed',
                  ),
            ),
        'complementary_cell_exposure',
      );
      block(
        cells.any((item) => item.cell.privacyStatus == 'suppressed'),
        'sparse_cell',
      );
      block(
        externalFacts.any(
          (fact) =>
              fact.knownUnitCount >= 1 &&
              fact.knownUnitCount <= 9 &&
              cells.any(
                (item) =>
                    item.report.periodKey == fact.periodKey &&
                    item.cell.regionId == fact.targetRegionId &&
                    item.cell.treeVersion == fact.targetTreeVersion &&
                    item.cell.categoryKey == fact.categoryKey,
              ),
        ),
        'external_fact_exposure',
      );
      block(
        cells.any(
          (item) =>
              item.cell.privacyStatus == 'displayed' &&
              (item.cell.valueCount! < 10 ||
                  item.cell.contributorCount < 3 ||
                  item.cell.maxContribution * 2 > item.cell.valueCount!),
        ),
        'threshold_error_exposure',
      );
      block(
        viewMode == 'original' &&
            cells.any(
              (item) => !locations.any(
                (location) =>
                    location.state == 'resolved' &&
                    location.includedInRegionCell &&
                    location.regionId == item.cell.regionId &&
                    location.treeVersion == item.cell.treeVersion,
              ),
            ),
        'original_provenance_missing',
      );
      block(
        viewMode == 'current' &&
            cells.any(
              (item) => !locations.any(
                (location) =>
                    location.state == 'resolved' &&
                    location.includedInRegionCell &&
                    ((location.regionId == item.cell.regionId &&
                            location.treeVersion == item.cell.treeVersion) ||
                        mappings.any(
                          (mapping) =>
                              mapping.fromRegionId == location.regionId &&
                              mapping.fromTreeVersion == location.treeVersion &&
                              mapping.toRegionId == item.cell.regionId &&
                              mapping.toTreeVersion == item.cell.treeVersion,
                        )),
              ),
            ),
        'current_mapping_missing',
      );
      block(
        locations.any(
          (location) =>
              location.state == 'pending_resolution' &&
              location.includedInRegionCell,
        ),
        'pending_resolution_not_reportable',
      );
      block(
        locations.any(
          (location) =>
              location.state == 'not_applicable' &&
              location.includedInRegionCell,
        ),
        'not_applicable_separate',
      );
      block(
        !const {'original', 'current'}.contains(viewMode) ||
            reports.any((report) => report.viewMode != viewMode),
        'mixed_view',
      );
      block(
        reports.any(
          (report) =>
              report.treeVersion != treeVersion ||
              report.cells.any(
                (cell) => cell.treeVersion != report.treeVersion,
              ),
        ),
        'mixed_tree_version',
      );
      block(
        !const {'smallest_region', 'coordinates'}.contains(regionGranularity) ||
            reports.any(
              (report) => !const {
                'smallest_region',
                'coordinates',
              }.contains(report.regionGranularity),
            ),
        'unknown_granularity',
      );
      block(
        reports.any(
          (report) =>
              !const {'fixed_nodes', 'coordinates'}.contains(report.scopeKind),
        ),
        'free_region_scope',
      );
      block(
        regionGranularity == 'coordinates' ||
            reports.any(
              (report) =>
                  report.regionGranularity == 'coordinates' ||
                  report.scopeKind == 'coordinates',
            ),
        'coordinate_dimension',
      );
      block(
        locations.any(
          (location) =>
              location.state == 'not_applicable' &&
              (location.regionId != null || location.treeVersion != null),
        ),
        'fake_not_applicable',
      );

      return ManagementRegionPrivacyAssessmentV1._(
        resultStatus: reasons.isEmpty ? 'approved' : 'blocked',
        reasonCodes: reasons,
      );
    } on FormatException {
      throw ArgumentError('invalid_management_region_privacy_probe');
    } on TypeError {
      throw ArgumentError('invalid_management_region_privacy_probe');
    }
  }
}

final class ManagementRegionPrivacyAssessmentV1 {
  ManagementRegionPrivacyAssessmentV1._({
    required this.resultStatus,
    required List<String> reasonCodes,
  }) : reasonCodes = List.unmodifiable(reasonCodes);

  final String resultStatus;
  final List<String> reasonCodes;

  Map<String, Object?> toJson() => {
    'probe_id': ManagementRegionPrivacyProbeV1.probeId,
    'query_fingerprint': ManagementRegionPrivacyProbeV1.queryFingerprint,
    'result_status': resultStatus,
    'reason_codes': reasonCodes,
  };
}

typedef _ReportCell = ({int reportIndex, _Report report, _Cell cell});
typedef _CellPairPredicate =
    bool Function(_ReportCell earlier, _ReportCell later);

bool _anyCellPair(List<_ReportCell> cells, _CellPairPredicate predicate) {
  for (final earlier in cells) {
    for (final later in cells) {
      if (later.reportIndex > earlier.reportIndex &&
          predicate(earlier, later)) {
        return true;
      }
    }
  }
  return false;
}

bool _sameCellCoordinate(_ReportCell earlier, _ReportCell later) =>
    earlier.report.periodKey == later.report.periodKey &&
    earlier.cell.regionId == later.cell.regionId &&
    earlier.cell.treeVersion == later.cell.treeVersion &&
    earlier.cell.categoryKey == later.cell.categoryKey;

final class _Report {
  const _Report({
    required this.reportKey,
    required this.periodKey,
    required this.viewMode,
    required this.treeVersion,
    required this.regionGranularity,
    required this.scopeKind,
    required this.cells,
  });

  final String reportKey;
  final String periodKey;
  final String viewMode;
  final String treeVersion;
  final String regionGranularity;
  final String scopeKind;
  final List<_Cell> cells;
}

final class _Cell {
  const _Cell({
    required this.regionId,
    required this.treeVersion,
    required this.privacyStatus,
    required this.valueCount,
    required this.contributorCount,
    required this.maxContribution,
    required this.categoryKey,
  });

  final String regionId;
  final String treeVersion;
  final String privacyStatus;
  final int? valueCount;
  final int contributorCount;
  final int maxContribution;
  final String categoryKey;
}

final class _Relationship {
  const _Relationship({
    required this.parentRegionId,
    required this.childRegionId,
    required this.treeVersion,
  });

  final String parentRegionId;
  final String childRegionId;
  final String treeVersion;
}

final class _Mapping {
  const _Mapping({
    required this.fromRegionId,
    required this.fromTreeVersion,
    required this.toRegionId,
    required this.toTreeVersion,
  });

  final String fromRegionId;
  final String fromTreeVersion;
  final String toRegionId;
  final String toTreeVersion;
}

final class _QueryOverlap {
  const _QueryOverlap({
    required this.leftRegionId,
    required this.leftTreeVersion,
    required this.rightRegionId,
    required this.rightTreeVersion,
  });

  final String leftRegionId;
  final String leftTreeVersion;
  final String rightRegionId;
  final String rightTreeVersion;
}

final class _LocationState {
  const _LocationState({
    required this.state,
    required this.regionId,
    required this.treeVersion,
    required this.includedInRegionCell,
  });

  final String state;
  final String? regionId;
  final String? treeVersion;
  final bool includedInRegionCell;
}

final class _ExternalFact {
  const _ExternalFact({
    required this.knownUnitCount,
    required this.targetRegionId,
    required this.targetTreeVersion,
    required this.periodKey,
    required this.categoryKey,
  });

  final int knownUnitCount;
  final String targetRegionId;
  final String targetTreeVersion;
  final String periodKey;
  final String categoryKey;
}

_Report _report(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'report_key',
    'period_key',
    'view_mode',
    'tree_version',
    'region_granularity',
    'scope_kind',
    'cells',
  });
  final cells = _list(map, 'cells').map(_cell).toList();
  if (cells.isEmpty) throw const FormatException('cells are empty');
  return _Report(
    reportKey: _string(map, 'report_key'),
    periodKey: _string(map, 'period_key'),
    viewMode: _string(map, 'view_mode'),
    treeVersion: _string(map, 'tree_version'),
    regionGranularity: _string(map, 'region_granularity'),
    scopeKind: _string(map, 'scope_kind'),
    cells: cells,
  );
}

_Cell _cell(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'region_id',
    'tree_version',
    'privacy_status',
    'value_count',
    'contributor_count',
    'max_contribution',
    'category_key',
  });
  final status = _string(map, 'privacy_status');
  if (!const {'displayed', 'suppressed'}.contains(status)) {
    throw const FormatException('unknown privacy status');
  }
  final valueCount = map['value_count'];
  if ((status == 'displayed' && valueCount == null) ||
      (status == 'suppressed' && valueCount != null)) {
    throw const FormatException('invalid protected value');
  }
  return _Cell(
    regionId: _string(map, 'region_id'),
    treeVersion: _string(map, 'tree_version'),
    privacyStatus: status,
    valueCount: valueCount == null ? null : _nonNegativeInt(valueCount),
    contributorCount: _nonNegativeInt(map['contributor_count']),
    maxContribution: _nonNegativeInt(map['max_contribution']),
    categoryKey: _string(map, 'category_key'),
  );
}

_Relationship _relationship(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'parent_region_id',
    'child_region_id',
    'tree_version',
  });
  final parent = _string(map, 'parent_region_id');
  final child = _string(map, 'child_region_id');
  if (parent == child) throw const FormatException('self relationship');
  return _Relationship(
    parentRegionId: parent,
    childRegionId: child,
    treeVersion: _string(map, 'tree_version'),
  );
}

_Mapping _mapping(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'from_region_id',
    'from_tree_version',
    'to_region_id',
    'to_tree_version',
  });
  return _Mapping(
    fromRegionId: _string(map, 'from_region_id'),
    fromTreeVersion: _string(map, 'from_tree_version'),
    toRegionId: _string(map, 'to_region_id'),
    toTreeVersion: _string(map, 'to_tree_version'),
  );
}

_QueryOverlap _queryOverlap(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'left_region_id',
    'left_tree_version',
    'right_region_id',
    'right_tree_version',
  });
  final leftRegionId = _string(map, 'left_region_id');
  final leftTreeVersion = _string(map, 'left_tree_version');
  final rightRegionId = _string(map, 'right_region_id');
  final rightTreeVersion = _string(map, 'right_tree_version');
  if (leftRegionId == rightRegionId && leftTreeVersion == rightTreeVersion) {
    throw const FormatException('self query overlap');
  }
  return _QueryOverlap(
    leftRegionId: leftRegionId,
    leftTreeVersion: leftTreeVersion,
    rightRegionId: rightRegionId,
    rightTreeVersion: rightTreeVersion,
  );
}

_LocationState _location(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'state',
    'region_id',
    'tree_version',
    'included_in_region_cell',
  });
  final state = _string(map, 'state');
  if (!const {
    'resolved',
    'pending_resolution',
    'not_applicable',
  }.contains(state)) {
    throw const FormatException('unknown location state');
  }
  final regionId = _nullableString(map['region_id']);
  final treeVersion = _nullableString(map['tree_version']);
  if (state == 'resolved' && (regionId == null || treeVersion == null)) {
    throw const FormatException('resolved location has no region');
  }
  if (state == 'pending_resolution' &&
      (regionId != null || treeVersion != null)) {
    throw const FormatException('pending location has a resolved region');
  }
  final included = map['included_in_region_cell'];
  if (included is! bool) throw const FormatException('invalid inclusion');
  return _LocationState(
    state: state,
    regionId: regionId,
    treeVersion: treeVersion,
    includedInRegionCell: included,
  );
}

_ExternalFact _externalFact(Object? value) {
  final map = _map(value);
  _expectKeys(map, const {
    'fact_kind',
    'known_unit_count',
    'target_region_id',
    'target_tree_version',
    'period_key',
    'category_key',
  });
  _string(map, 'fact_kind');
  return _ExternalFact(
    knownUnitCount: _nonNegativeInt(map['known_unit_count']),
    targetRegionId: _string(map, 'target_region_id'),
    targetTreeVersion: _string(map, 'target_tree_version'),
    periodKey: _string(map, 'period_key'),
    categoryKey: _string(map, 'category_key'),
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('expected object');
  return value.map((key, value) => MapEntry(key as String, value));
}

List<Object?> _list(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List) throw const FormatException('expected list');
  return value.cast<Object?>();
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('expected string');
  }
  return value;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('expected nullable string');
  }
  return value;
}

int _nonNegativeInt(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('expected non-negative integer');
  }
  return value;
}

void _expectKeys(Map<String, Object?> map, Set<String> expected) {
  if (map.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(map.keys.toSet()).isNotEmpty) {
    throw const FormatException('object keys do not match');
  }
}
