import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/targets/personal_target_merge_projection_panel.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_projection.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../../support/fake_identity_session.dart';
import '../../support/fake_session_context_gateway.dart';

void main() {
  testWidgets('reads only on action and preserves borrowed resources', (
    tester,
  ) async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    expect(h.gateway.requests, isEmpty);
    expect(find.text(h.text.t('mergeProjectionEmpty')), findsOneWidget);
    final contextCalls = h.contexts.receivedTokens.length;
    await h.read(tester);
    expect(h.gateway.requests, hasLength(1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await h.complete(tester);
    expect(find.text('姓名或机构名称: Synthetic same name'), findsNWidgets(3));
    expect(h.contexts.receivedTokens, hasLength(contextCalls));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(h.gateway.closed, isFalse);
    expect(h.identity.isClosed, isFalse);
    expect(h.contexts.isClosed, isFalse);
    expect(h.session.current.stage, AppSessionStage.ready);
  });

  testWidgets('keeps NULL selection and each original relationship separate', (
    tester,
  ) async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    await h.read(tester);
    await h.complete(tester);
    expect(find.text('电话: 未提供'), findsNWidgets(2));
    expect(find.text('电话: source-a-phone'), findsOneWidget);
    expect(find.text('来源 2 · source-b'), findsOneWidget);
    expect(find.text('来源 1 · source-a'), findsNWidgets(2));
    final a = find.byKey(const ValueKey('merge-projection-source-1'));
    final b = find.byKey(const ValueKey('merge-projection-source-2'));
    expect(
      find.descendant(of: a, matching: find.text('关系阶段: 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: a, matching: find.text('显示阶段数值: 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: a, matching: find.text('共享跟进备注: source-a-note')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: b, matching: find.text('关系阶段: 3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: b, matching: find.text('项目关系状态: 暂停跟进')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: b, matching: find.text('共享跟进备注: source-b-note')),
      findsOneWidget,
    );
    expect(find.text('关系阶段 1 · 显示阶段数值 2: source-a-alias'), findsOneWidget);
    expect(find.text('关系阶段 3 · 显示阶段数值 6: source-b-alias'), findsOneWidget);
    expect(
      find.text('较早资料复核时间（UTC）: 2027-01-01T00:00:00.000Z'),
      findsOneWidget,
    );
    expect(
      find.text('本来源资料复核时间（UTC）: 2027-02-01T00:00:00.000Z'),
      findsOneWidget,
    );
  });

  testWidgets('discloses source facts in server order without partner lookup', (
    tester,
  ) async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    await h.read(tester);
    await h.complete(tester);
    expect(find.text('接触 ID: z-contact'), findsNothing);
    expect(find.text('关系 ID: z-institution-link'), findsNothing);
    await _expand(tester, 'merge-projection-contacts-1');
    expect(find.text('接触 ID: z-contact'), findsOneWidget);
    expect(find.text('合并代次 ID: 无合并绑定'), findsOneWidget);
    expect(find.text('合并代次 ID: old-generation'), findsOneWidget);
    expect(find.text('这个对象的当次反应（0–4，可选）: 未提供'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('接触 ID: z-contact')).dy,
      lessThan(tester.getTopLeft(find.text('接触 ID: a-contact')).dy),
    );
    expect(find.text('接触 ID: source-b-contact'), findsNothing);
    await _expand(tester, 'merge-projection-institutions-1');
    expect(find.text('机构对象: partner-id-only'), findsNWidgets(2));
    expect(find.text('以下为当前关系事实，不含修订历史。'), findsOneWidget);
    expect(find.text('历史事件'), findsNothing);
    expect(
      tester.getTopLeft(find.text('关系 ID: z-institution-link')).dy,
      lessThan(tester.getTopLeft(find.text('关系 ID: a-institution-link')).dy),
    );
    expect(h.gateway.requests, hasLength(1));
  });

  testWidgets('reload clears PII and resets disclosure before the response', (
    tester,
  ) async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    await h.read(tester);
    await h.complete(tester);
    await _expand(tester, 'merge-projection-contacts-1');
    await h.read(tester);
    expect(find.textContaining('Synthetic same name'), findsNothing);
    expect(find.text('接触 ID: z-contact'), findsNothing);
    await h.complete(tester);
    expect(find.text('接触 ID: z-contact'), findsNothing);
    expect(h.gateway.requests, hasLength(2));
  });

  testWidgets('failure is value-free and retry only reads again', (
    tester,
  ) async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    final calls = h.contexts.receivedTokens.length;
    await h.read(tester);
    h.gateway.requests.last.result.completeError(
      StateError('private-raw-error'),
    );
    await tester.pump();
    expect(find.text(h.text.t('mergeProjectionFailed')), findsOneWidget);
    expect(find.textContaining('private-raw-error'), findsNothing);
    await h.read(tester);
    await h.complete(tester);
    expect(h.gateway.requests, hasLength(2));
    expect(h.contexts.receivedTokens, hasLength(calls));
  });

  for (final change in ['identity', 'project', 'capability']) {
    testWidgets('$change invalidation withdraws PII without another read', (
      tester,
    ) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await h.read(tester);
      await h.complete(tester);
      if (change == 'identity') {
        h.identity.emit(const IdentitySnapshot.signedOut());
      } else {
        await h.select(
          _context(
            projectId: change == 'project' ? 'other-project' : null,
            capabilities: change == 'capability'
                ? {'view_assigned_target_pii'}
                : null,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic same name'), findsNothing);
      expect(find.text(h.text.t('mergeProjectionInvalidated')), findsOneWidget);
      expect(h.gateway.requests, hasLength(1));
    });
  }

  testWidgets(
    'invalidation rejects an in-flight result after identity recovers',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await h.read(tester);
      final request = h.gateway.requests.single;
      h.identity.emit(const IdentitySnapshot.signedOut());
      h.identity.emit(_identity());
      await tester.pumpAndSettle();
      expect(request.isCurrent(), isFalse);
      request.result.complete(
        PersonalTargetMergeProjectionReady(syntheticMergeProjection()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic same name'), findsNothing);
      expect(find.text(h.text.t('mergeProjectionInvalidated')), findsOneWidget);
      expect(h.gateway.requests, hasLength(1));
    },
  );

  testWidgets(
    'NULL note and alias do not borrow source values and empty strings stay empty',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await h.read(tester);
      h.gateway.requests.last.result.complete(
        PersonalTargetMergeProjectionReady(
          syntheticMergeProjection(nullFields: true),
        ),
      );
      await tester.pumpAndSettle();
      final b = find.byKey(const ValueKey('merge-projection-source-2'));
      expect(
        find.descendant(of: b, matching: find.text('共享跟进备注: 未提供')),
        findsOneWidget,
      );
      expect(find.text('关系阶段 3 · 显示阶段数值 6: 未提供'), findsOneWidget);
      expect(find.text('邮箱: 未提供'), findsNWidgets(2));
      expect(find.text('邮箱: source-a@example.test'), findsOneWidget);
      expect(find.text('电话: '), findsOneWidget);
      expect(find.text('电话: 未提供'), findsNWidgets(2));
      expect(find.text('来源 2 · source-b'), findsNWidgets(2));
    },
  );

  testWidgets(
    'generation change retires in-flight and held content without auto-read',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await h.read(tester);
      final old = h.gateway.requests.last;
      await tester.pumpWidget(h.widget(generationId: 'generation-b'));
      expect(old.isCurrent(), isFalse);
      old.result.complete(
        PersonalTargetMergeProjectionReady(syntheticMergeProjection()),
      );
      await tester.pump();
      expect(find.textContaining('Synthetic same name'), findsNothing);
      expect(h.gateway.requests, hasLength(1));
      await h.read(tester);
      await h.complete(tester, generationId: 'generation-b');
      expect(h.gateway.requests.last.generationId, 'generation-b');
      await tester.pumpWidget(h.widget(generationId: 'generation-c'));
      expect(find.textContaining('Synthetic same name'), findsNothing);
      expect(h.gateway.requests, hasLength(2));
    },
  );

  for (final dependency in ['gateway', 'identity', 'session']) {
    testWidgets(
      '$dependency replacement retires controller and keeps borrowed resources open',
      (tester) async {
        final h = await _Harness.start();
        final replacement = await _Harness.start();
        addTearDown(h.close);
        addTearDown(replacement.close);
        await tester.pumpWidget(h.widget());
        await h.read(tester);
        final old = h.gateway.requests.last;
        await tester.pumpWidget(
          h.widget(
            gateway: dependency == 'gateway' ? replacement.gateway : null,
            identity: dependency == 'identity' ? replacement.identity : null,
            session: dependency == 'session' ? replacement.session : null,
          ),
        );
        expect(old.isCurrent(), isFalse);
        old.result.complete(
          PersonalTargetMergeProjectionReady(syntheticMergeProjection()),
        );
        await tester.pump();
        expect(find.textContaining('Synthetic same name'), findsNothing);
        expect(h.gateway.requests, hasLength(1));
        expect(replacement.gateway.requests, isEmpty);
        expect(h.gateway.closed, isFalse);
        expect(h.identity.isClosed, isFalse);
        expect(h.contexts.isClosed, isFalse);
      },
    );
  }

  for (final locale in ['zh', 'en']) {
    testWidgets(
      '$locale institution NULL and empty facts fit 360px at 200% in dark mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _Harness.start(locale: locale);
        addTearDown(h.close);
        await tester.pumpWidget(h.widget(dark: true, large: true));
        await h.read(tester);
        h.gateway.requests.last.result.complete(
          PersonalTargetMergeProjectionReady(
            syntheticMergeProjection(
              institution: true,
              empty: true,
              longText: true,
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text(
            '${h.text.t('mergeProjectionType')}: ${h.text.t('targetsInstitution')}',
          ),
          findsNWidgets(2),
        );
        expect(
          find.text(h.text.t('targetsNoProjectRelationship')),
          findsNWidgets(2),
        );
        await _expand(tester, 'merge-projection-contacts-1');
        expect(find.text(h.text.t('mergeProjectionNoFacts')), findsOneWidget);
        await _expand(tester, 'merge-projection-institutions-2');
        expect(find.text(h.text.t('mergeProjectionNoFacts')), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('long source IDs and notes wrap with expanded facts at 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = await _Harness.start(locale: 'en');
    addTearDown(h.close);
    await tester.pumpWidget(h.widget(large: true));
    await h.read(tester);
    h.gateway.requests.last.result.complete(
      PersonalTargetMergeProjectionReady(
        syntheticMergeProjection(longText: true),
      ),
    );
    await tester.pumpAndSettle();
    await _expand(tester, 'merge-projection-contacts-1');
    await _expand(tester, 'merge-projection-institutions-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard disclosure exposes semantics immediately with reduced motion',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(h.widget(reduceMotion: true));
      await h.read(tester);
      await h.complete(tester);
      final tile = find.byKey(const ValueKey('merge-projection-contacts-1'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      final focus = Focus.of(tester.element(find.text('接触对象关联 (2)')));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('接触 ID: z-contact'), findsOneWidget);
      expect(
        tester.widget<ExpansionTile>(tile).expansionAnimationStyle!.duration,
        Duration.zero,
      );
      expect(
        tester.getSemantics(find.text('接触对象关联 (2)')).getSemanticsData().hint,
        contains(MaterialLocalizations.of(tester.element(tile)).collapsedHint),
      );
      semantics.dispose();
    },
  );
}

Future<void> _expand(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey(key));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: tile, matching: find.byType(ListTile)).first,
  );
  await tester.pumpAndSettle();
}

/// Synthetic presentation data. It does not establish authorization or real-user behavior.
PersonalTargetMergeProjection syntheticMergeProjection({
  String generationId = 'generation-a',
  bool institution = false,
  bool empty = false,
  bool longText = false,
  bool nullFields = false,
}) {
  final type = institution
      ? PromotionTargetType.institution
      : PromotionTargetType.person;
  final name = longText
      ? List.filled(8, 'Synthetic 长名称').join(' ')
      : 'Synthetic same name';
  final sourceA = longText
      ? 'source-a-${List.filled(12, 'long-id').join()}'
      : 'source-a';
  final sourceB = longText
      ? 'source-b-${List.filled(12, 'long-id').join()}'
      : 'source-b';
  return PersonalTargetMergeProjection(
    generationId: generationId,
    workspaceId: _context().workspace.id,
    projectId: _context().project.id,
    targetType: type,
    retainedTargetId: sourceA,
    displayNameSourceTargetId: sourceA,
    phoneSourceTargetId: sourceB,
    emailSourceTargetId: nullFields ? sourceB : sourceA,
    displayName: name,
    phone: null,
    email: nullFields ? null : 'source-a@example.test',
    reviewDueAtUtc: DateTime.utc(2027),
    sources: [
      for (final id in [sourceA, sourceB])
        PersonalTargetMergeProjectionSource(
          targetId: id,
          profile: PersonalTargetMergeSourceProfile(
            targetId: id,
            targetType: type,
            displayName: name,
            phone: id == sourceA ? (nullFields ? '' : 'source-a-phone') : null,
            email: id == sourceA ? 'source-a@example.test' : null,
            createdAtUtc: DateTime.utc(2026),
          ),
          reviewDueAtUtc: DateTime.utc(2027, id == sourceA ? 2 : 1),
          projectRelationship: empty
              ? null
              : PersonalTargetMergeProjectRelationship(
                  targetId: id,
                  projectId: _context().project.id,
                  stage: id == sourceA ? 1 : 3,
                  displayStage: id == sourceA ? 2 : 6,
                  lifecycleStatus: id == sourceA
                      ? PromotionTargetRelationshipLifecycle.active
                      : PromotionTargetRelationshipLifecycle.paused,
                  followUpNote: nullFields && id == sourceB
                      ? null
                      : longText
                      ? List.filled(16, '$id-note').join(' ')
                      : '$id-note',
                  revisionNumber: id == sourceA ? 7 : 9,
                  updatedAtUtc: DateTime.utc(2026, 10),
                  stageAliases: [
                    PromotionTargetStageAlias(
                      stage: id == sourceA ? 1 : 3,
                      displayStage: id == sourceA ? 2 : 6,
                      displayName: nullFields && id == sourceB
                          ? null
                          : '$id-alias',
                    ),
                  ],
                ),
          contactLinks: empty
              ? []
              : [
                  for (final contact
                      in id == sourceA
                          ? ['z-contact', 'a-contact']
                          : ['source-b-contact'])
                    PersonalTargetMergeContactLink(
                      contactId: contact,
                      revisionNumber: 3,
                      promotionTargetId: id,
                      responseLevel: contact == 'z-contact' ? null : 4,
                      followUpConsent: ContactFollowUpConsent.unknown,
                      institutionRepresentativeConfirmed: institution,
                      confirmedProjectEntry: false,
                      mergeGenerationId: contact == 'z-contact'
                          ? null
                          : 'old-generation',
                    ),
                ],
          institutionRelationships: empty
              ? []
              : [
                  for (final relation in [
                    'z-institution-link',
                    'a-institution-link',
                  ])
                    PersonalTargetMergeInstitutionRelationship(
                      id: relation,
                      personTargetId: institution ? 'partner-id-only' : id,
                      institutionTargetId: institution ? id : 'partner-id-only',
                      kind: TargetInstitutionRelationshipKind
                          .membershipAffiliation,
                      roleDescription: null,
                      startedAtUtc: DateTime.utc(2026, 2),
                      endedAtUtc: relation == 'z-institution-link'
                          ? null
                          : DateTime.utc(2026, 3),
                      status: relation == 'z-institution-link'
                          ? TargetInstitutionRelationshipStatus.active
                          : TargetInstitutionRelationshipStatus.ended,
                      revisionNumber: 2,
                    ),
                ],
        ),
    ],
  );
}

IdentitySnapshot _identity() => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: const IdentityPrincipal(
    externalSubject: 'synthetic-owner',
    email: 'synthetic@example.test',
  ),
  expiresAt: DateTime.utc(2030),
);

TrustedSessionContext _context({
  String? projectId,
  Set<String>? capabilities,
}) => TrustedSessionContext(
  appUserId: syntheticSessionContext.appUserId,
  workspace: const WorkspaceContext(
    id: 'synthetic-workspace',
    kind: WorkspaceKind.personal,
    name: 'Synthetic workspace',
  ),
  project: ProjectContext(
    id: projectId ?? 'synthetic-project',
    name: 'Synthetic project',
  ),
  questionnaireVersion: syntheticSessionContext.questionnaireVersion,
  capabilities:
      capabilities ??
      {'view_assigned_target_pii', 'manage_assigned_target_merges'},
);

final class _Harness {
  _Harness(this.identity, this.contexts, this.session, this.text);
  final FakeIdentitySession identity;
  final FakeSessionContextGateway contexts;
  final AppSession session;
  final AppStrings text;
  final gateway = _Gateway();

  static Future<_Harness> start({String locale = 'zh'}) async {
    final identity = FakeIdentitySession(initial: _identity());
    final contexts = FakeSessionContextGateway(
      context: _context(),
      selectedContexts: {},
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: contexts,
    );
    await session.start();
    return _Harness(identity, contexts, session, AppStrings(locale));
  }

  Widget widget({
    String generationId = 'generation-a',
    _Gateway? gateway,
    IdentitySession? identity,
    AppSession? session,
    bool dark = false,
    bool large = false,
    bool reduceMotion = false,
  }) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF14746F),
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
    ),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(large ? 2 : 1),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PersonalTargetMergeProjectionPanel(
              text: text,
              identitySession: identity ?? this.identity,
              appSession: session ?? this.session,
              gateway: gateway ?? this.gateway,
              generationId: generationId,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> read(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('merge-projection-read'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
  }

  Future<void> complete(
    WidgetTester tester, {
    String generationId = 'generation-a',
  }) async {
    gateway.requests.last.result.complete(
      PersonalTargetMergeProjectionReady(
        syntheticMergeProjection(generationId: generationId),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(TrustedSessionContext context) async {
    contexts.selectedContexts[context.project.id] = context;
    await session.selectProject(context.project.id);
  }

  Future<void> close() async {
    await session.close();
    await identity.close();
  }
}

final class _Request {
  _Request(this.generationId, this.isCurrent);
  final String generationId;
  final bool Function() isCurrent;
  final result = Completer<PersonalTargetMergeProjectionResult>();
}

final class _Gateway implements PersonalTargetMergeProjectionGateway {
  final requests = <_Request>[];
  bool closed = false;

  @override
  Future<PersonalTargetMergeProjectionResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) {
    final request = _Request(generationId, requestIsCurrent);
    requests.add(request);
    return request.result.future;
  }

  @override
  Future<void> close() async => closed = true;
}
