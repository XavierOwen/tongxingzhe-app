import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_controller.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/questionnaire_admin/questionnaire_admin_screen.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_administration.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  testWidgets('管理员从空白草稿设计、预览差异并发布', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final controller = AppController(
      database: database,
      clock: const _Clock(),
      idGenerator: _Ids(),
    );
    final gateway = _Gateway();
    final ids = _Ids();

    await tester.pumpWidget(
      MaterialApp(
        home: _Launcher(
          screen: QuestionnaireAdminScreen(
            controller: controller,
            gateway: gateway,
            idGenerator: ids,
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('create-blank-questionnaire-draft')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-questionnaire-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('question-editor-prompt')),
      '愿意继续了解吗？',
    );
    await tester.tap(find.byKey(const ValueKey('save-questionnaire-question')));
    await tester.pumpAndSettle();

    expect(find.text('愿意继续了解吗？'), findsOneWidget);
    await tester.tap(find.text('模拟预览'));
    await tester.pumpAndSettle();
    expect(find.textContaining('愿意继续了解吗？'), findsOneWidget);

    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(find.text('question-1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('questionnaire-publication-note')),
      '首次正式问卷',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('publish-questionnaire-draft')));
    await tester.pumpAndSettle();

    expect(find.text('已发布'), findsOneWidget);
    expect(gateway.publishedNote, '首次正式问卷');
    expect(gateway.savedDefinition!.questions.single.prompt, '愿意继续了解吗？');
  });

  testWidgets('编辑器保留多条件规则并可切换 all 或 any', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final controller = AppController(
      database: database,
      clock: const _Clock(),
      idGenerator: _Ids(),
    );
    final gateway = _Gateway(current: _conditionalCurrent);

    await tester.pumpWidget(
      MaterialApp(
        home: _Launcher(
          screen: QuestionnaireAdminScreen(
            controller: controller,
            gateway: gateway,
            idGenerator: _Ids(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制为草稿'));
    await tester.pumpAndSettle();

    final targetCard = find.byKey(
      const ValueKey('design-question-conditional-target'),
    );
    await tester.tap(
      find.descendant(
        of: targetCard,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('question-rule-condition-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('question-rule-condition-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('question-rule-add-condition')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('question-rule-condition-2')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('question-rule-remove-condition-2')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('question-rule-condition-2')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('question-rule-match')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部条件').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-questionnaire-question')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-questionnaire-draft')));
    await tester.pumpAndSettle();

    final savedRule = gateway.savedDefinition!.questions.last.displayRule!;
    expect(savedRule.match, QuestionnaireVisibilityMatch.all);
    expect(savedRule.conditions, hasLength(2));
    expect(
      savedRule.conditions.map((condition) => condition.sourceQuestionId),
      ['consent-source', 'note-source'],
    );
  });
}

final class _Launcher extends StatefulWidget {
  const _Launcher({required this.screen});

  final Widget screen;

  @override
  State<_Launcher> createState() => _LauncherState();
}

final class _LauncherState extends State<_Launcher> {
  var _published = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: _published
          ? const Text('已发布')
          : FilledButton(
              onPressed: () async {
                final result = await Navigator.of(
                  context,
                ).push<bool>(MaterialPageRoute(builder: (_) => widget.screen));
                if (mounted) setState(() => _published = result == true);
              },
              child: const Text('打开'),
            ),
    ),
  );
}

final class _Gateway implements QuestionnaireAdministrationGateway {
  _Gateway({QuestionnaireVersion? current})
    : _currentVersion = current ?? _current;

  final QuestionnaireVersion _currentVersion;
  QuestionnaireDesignDraft? draft;
  QuestionnaireVersion? savedDefinition;
  String? publishedNote;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load() async => QuestionnaireAdministrationSuccess(
    QuestionnaireAdministrationSnapshot(
      currentVersionId: _currentVersion.id,
      versions: [
        QuestionnairePublishedVersionSummary(
          id: _currentVersion.id,
          versionNumber: 1,
          isCurrent: true,
          publishedAtUtc: DateTime.utc(2026, 8, 6),
          publishedByAppUserId: null,
          publicationNote: null,
        ),
      ],
      drafts: const [],
    ),
  );

  @override
  Future<QuestionnaireVersion?> readPublishedVersion(String versionId) async =>
      _currentVersion;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId}) async {
    draft = QuestionnaireDesignDraft(
      id: 'draft-1',
      projectId: 'project-1',
      sourceVersionId: sourceVersionId,
      revision: 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6),
      definition: QuestionnaireVersion(
        id: 'draft-1',
        projectId: 'project-1',
        versionNumber: 1,
        questions: sourceVersionId == _currentVersion.id
            ? _currentVersion.questions
            : const [],
      ),
    );
    return QuestionnaireAdministrationSuccess(draft!);
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  }) async {
    savedDefinition = definition;
    this.draft = QuestionnaireDesignDraft(
      id: draft.id,
      projectId: draft.projectId,
      sourceVersionId: draft.sourceVersionId,
      revision: draft.revision + 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6, 1),
      definition: QuestionnaireVersion(
        id: draft.id,
        projectId: draft.projectId,
        versionNumber: draft.revision + 1,
        questions: definition.questions,
      ),
    );
    return QuestionnaireAdministrationSuccess(this.draft!);
  }

  @override
  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  }) async {
    publishedNote = publicationNote;
    final published = QuestionnaireVersion(
      id: 'version-2',
      projectId: draft.projectId,
      versionNumber: 2,
      questions: draft.definition.questions,
    );
    return QuestionnaireAdministrationSuccess(
      QuestionnairePublication(
        summary: QuestionnairePublishedVersionSummary(
          id: published.id,
          versionNumber: 2,
          isCurrent: true,
          publishedAtUtc: DateTime.utc(2026, 8, 6, 2),
          publishedByAppUserId: 'manager-1',
          publicationNote: publicationNote,
        ),
        version: published,
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final _current = QuestionnaireVersion(
  id: 'version-1',
  projectId: 'project-1',
  versionNumber: 1,
  questions: const [],
);

final _conditionalCurrent = QuestionnaireVersion(
  id: 'conditional-version',
  projectId: 'project-1',
  versionNumber: 1,
  questions: [
    QuestionnaireQuestion(
      id: 'consent-source',
      position: 1,
      prompt: '愿意继续了解吗？',
      type: QuestionnaireQuestionType.boolean,
      required: true,
      allowUnknown: false,
      allowRefused: true,
      allowNotApplicable: false,
    ),
    QuestionnaireQuestion(
      id: 'note-source',
      position: 2,
      prompt: '已有补充说明吗？',
      type: QuestionnaireQuestionType.shortText,
      required: false,
      allowUnknown: false,
      allowRefused: true,
      allowNotApplicable: true,
      maximumLength: 120,
    ),
    QuestionnaireQuestion(
      id: 'conditional-target',
      position: 3,
      prompt: '条件问题',
      type: QuestionnaireQuestionType.boolean,
      required: false,
      allowUnknown: false,
      allowRefused: true,
      allowNotApplicable: true,
      displayRule: QuestionnaireVisibilityRule(
        match: QuestionnaireVisibilityMatch.any,
        conditions: const [
          QuestionnaireVisibilityCondition(
            sourceQuestionId: 'consent-source',
            operator: QuestionnaireVisibilityOperator.equals,
            operand: true,
          ),
          QuestionnaireVisibilityCondition(
            sourceQuestionId: 'note-source',
            operator: QuestionnaireVisibilityOperator.isAnswered,
          ),
        ],
      ),
    ),
  ],
);

final class _Ids implements IdGenerator {
  var _next = 0;

  @override
  String next() => switch (_next++) {
    0 => 'question-1',
    _ => 'publication-request',
  };
}

final class _Clock implements AppClock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 8, 6);
}
