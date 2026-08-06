import 'package:drift/drift.dart';

/// 本机缓存的不可变已发布问卷版本。
class DbQuestionnaireVersions extends Table {
  TextColumn get questionnaireVersionId => text()();
  TextColumn get projectId => text()();
  IntColumn get versionNumber => integer()();
  TextColumn get status => text()();
  DateTimeColumn get installedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {questionnaireVersionId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(questionnaire_version_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (version_number > 0)',
    "CHECK (status = 'published')",
    'UNIQUE (project_id, version_number)',
  ];
}

/// 已发布版本中的问题；显示规则是已验证的受限声明合同，不执行代码。
class DbQuestionnaireQuestions extends Table {
  TextColumn get questionnaireVersionId =>
      text().references(DbQuestionnaireVersions, #questionnaireVersionId)();
  TextColumn get questionId => text()();
  IntColumn get position => integer()();
  TextColumn get prompt => text()();
  TextColumn get questionType => text()();
  BoolColumn get isRequired => boolean()();
  BoolColumn get allowUnknown => boolean()();
  BoolColumn get allowRefused => boolean()();
  BoolColumn get allowNotApplicable => boolean()();
  IntColumn get minimumSelections => integer().nullable()();
  IntColumn get maximumSelections => integer().nullable()();
  TextColumn get numberKind => text().nullable()();
  TextColumn get unit => text().nullable()();
  RealColumn get minimum => real().nullable()();
  RealColumn get maximum => real().nullable()();
  IntColumn get maximumLength => integer().nullable()();
  TextColumn get displayRuleJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {questionnaireVersionId, questionId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(question_id)) > 0)',
    'CHECK (position > 0)',
    'CHECK (length(trim(prompt)) > 0)',
    "CHECK (question_type IN ('boolean', 'single_choice', "
        "'ordinal_choice', 'multi_choice', 'number', 'date', "
        "'short_text', 'long_text'))",
    "CHECK ((question_type = 'multi_choice' AND minimum_selections > 0 AND "
        'maximum_selections >= minimum_selections) OR '
        "(question_type <> 'multi_choice' AND minimum_selections IS NULL AND "
        'maximum_selections IS NULL))',
    "CHECK ((question_type = 'number' AND number_kind IN ('integer', "
        "'decimal') AND (minimum IS NULL OR maximum IS NULL OR "
        'minimum <= maximum)) OR '
        "(question_type <> 'number' AND number_kind IS NULL AND unit IS NULL "
        'AND minimum IS NULL AND maximum IS NULL))',
    "CHECK ((question_type IN ('short_text', 'long_text') AND "
        'maximum_length > 0) OR '
        "(question_type NOT IN ('short_text', 'long_text') AND "
        'maximum_length IS NULL))',
    'CHECK (display_rule_json IS NULL OR '
        '(json_valid(display_rule_json) AND '
        "json_type(display_rule_json) = 'object'))",
    'UNIQUE (questionnaire_version_id, position)',
  ];
}

/// 选择题的稳定选项 ID 与显示文字。普通单选不从 position 获得序数语义。
class DbQuestionnaireOptions extends Table {
  TextColumn get questionnaireVersionId =>
      text().references(DbQuestionnaireVersions, #questionnaireVersionId)();
  TextColumn get questionId => text()();
  TextColumn get optionId => text()();
  IntColumn get position => integer()();
  TextColumn get label => text()();

  @override
  Set<Column<Object>> get primaryKey => {
    questionnaireVersionId,
    questionId,
    optionId,
  };

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(question_id)) > 0)',
    'CHECK (length(trim(option_id)) > 0)',
    'CHECK (position > 0)',
    'CHECK (length(trim(label)) > 0)',
    'UNIQUE (questionnaire_version_id, question_id, position)',
  ];
}

/// 管理端显式保存时先落本机的工作副本；发布仍只能由 Backend 事务完成。
class DbQuestionnaireDraftWorkingCopies extends Table {
  TextColumn get questionnaireDraftId => text()();
  TextColumn get projectId => text()();
  TextColumn get sourceVersionId => text().nullable()();
  IntColumn get baseRevision => integer()();
  TextColumn get definitionJson => text()();
  BoolColumn get hasLocalChanges => boolean()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {questionnaireDraftId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(questionnaire_draft_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (base_revision > 0)',
    'CHECK (json_valid(definition_json) AND '
        "json_type(definition_json) = 'object')",
  ];
}
