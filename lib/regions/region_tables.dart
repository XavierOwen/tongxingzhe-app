import 'package:drift/drift.dart';

import '../features/contact_journal/contact_tables.dart';

/// 不可变区域树版本中的节点。父键指向同一版本的唯一规范父级。
class DbCanonicalRegionVersions extends Table {
  TextColumn get regionVersionKey => text()();
  TextColumn get regionId => text()();
  TextColumn get treeVersion => text()();
  TextColumn get parentRegionVersionKey => text().nullable().references(
    DbCanonicalRegionVersions,
    #regionVersionKey,
  )();
  TextColumn get canonicalName => text()();
  TextColumn get kind => text()();
  TextColumn get attributesJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {regionVersionKey};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {regionId, treeVersion},
  ];

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(region_id)) > 0)',
    'CHECK (length(trim(tree_version)) > 0)',
    'CHECK (length(trim(canonical_name)) > 0)',
    "CHECK (kind IN ('country', 'admin_area', 'city', 'district', "
        "'neighborhood', 'street', 'institution', 'venue', 'other'))",
  ];
}

/// 已提交接触对规范区域版本节点的真正外键。
class DbContactRegionAssignments extends Table {
  TextColumn get contactId => text().references(DbContactRecords, #contactId)();
  TextColumn get regionVersionKey =>
      text().references(DbCanonicalRegionVersions, #regionVersionKey)();

  @override
  Set<Column<Object>> get primaryKey => {contactId};
}

/// 草稿对规范区域版本节点的真正外键；草稿删除时由模块先删除该行。
class DbDraftRegionAssignments extends Table {
  TextColumn get draftId => text().references(DbContactDrafts, #draftId)();
  TextColumn get regionVersionKey =>
      text().references(DbCanonicalRegionVersions, #regionVersionKey)();

  @override
  Set<Column<Object>> get primaryKey => {draftId};
}
