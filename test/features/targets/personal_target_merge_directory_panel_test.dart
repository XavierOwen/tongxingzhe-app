import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/targets/personal_target_merge_directory_panel.dart';
import 'package:tongxingzhe_app/features/targets/personal_target_merge_projection_panel.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_directory.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_projection.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../../support/fake_identity_session.dart';
import '../../support/fake_session_context_gateway.dart';

void main() {
  testWidgets(
    'English large selector label wraps and keyboard confirms selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget(large: true, locale: 'en'));
      await h.read(tester);
      h.directory.complete(_page());
      await tester.pumpAndSettle();
      final label = find.text(const AppStrings('en').t('mergeDirectorySelect'));
      expect(tester.getSize(label).height, greaterThan(40));
      final selector = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(PersonalTargetMergeProjectionPanel), findsOneWidget);
      expect(h.projection.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'directory selection and detail reads are three explicit actions',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      expect(h.directory.pending, isEmpty);
      expect(h.projection.calls, 0);
      final resolves = h.contexts.receivedTokens.length;
      await h.read(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      h.directory.complete(_page());
      await tester.pumpAndSettle();
      expect(find.byType(PersonalTargetMergeProjectionPanel), findsNothing);
      await h.select(tester);
      expect(h.projection.calls, 0);
      expect(find.byType(PersonalTargetMergeProjectionPanel), findsOneWidget);
      final detail = find.byKey(const ValueKey('merge-projection-read'));
      await tester.ensureVisible(detail);
      await tester.tap(detail);
      await tester.pumpAndSettle();
      expect(h.projection.calls, 1);
      expect(h.contexts.receivedTokens, hasLength(resolves));
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(h.directory.closed, isFalse);
      expect(h.projection.closed, isFalse);
      expect(h.identity.isClosed, isFalse);
    },
  );

  for (final nextPage in [false, true]) {
    testWidgets(
      '${nextPage ? 'paging' : 'refresh'} clears the old selection before awaiting',
      (tester) async {
        final h = await _Harness.start();
        addTearDown(h.close);
        await tester.pumpWidget(h.widget());
        await h.read(tester);
        h.directory.complete(_page(next: _generation));
        await tester.pumpAndSettle();
        await h.select(tester);
        await tester.ensureVisible(
          find.byKey(
            ValueKey(
              nextPage ? 'merge-directory-next' : 'merge-directory-read',
            ),
          ),
        );
        await tester.tap(
          find.byKey(
            ValueKey(
              nextPage ? 'merge-directory-next' : 'merge-directory-read',
            ),
          ),
        );
        await tester.pump();
        expect(h.directory.cursors.last, nextPage ? _generation : isNull);
        expect(find.byType(PersonalTargetMergeProjectionPanel), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        h.directory.complete(_page(id: _secondGeneration));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalTargetMergeProjectionPanel), findsNothing);
        expect(h.projection.calls, 0);
      },
    );
  }

  testWidgets(
    'sign out removes the page and selection and rejects late results',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await h.read(tester);
      h.directory.complete(_page());
      await tester.pumpAndSettle();
      await h.select(tester);
      h.identity.emit(const IdentitySnapshot.signedOut());
      await tester.pumpAndSettle();
      expect(find.byType(PersonalTargetMergeProjectionPanel), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        find.text(const AppStrings('zh').t('mergeDirectoryInvalidated')),
        findsOneWidget,
      );
    },
  );

  testWidgets('failure can be retried and an empty page has no selector', (
    tester,
  ) async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    await h.read(tester);
    h.directory.pending.last.complete(
      const PersonalTargetMergeDirectoryRejected(
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(const AppStrings('zh').t('mergeDirectoryFailed')),
      findsOneWidget,
    );
    await h.read(tester);
    h.directory.complete(
      PersonalTargetMergeDirectory(
        workspaceId: syntheticSessionContext.workspace.id,
        projectId: syntheticSessionContext.project.id,
        items: [],
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(const AppStrings('zh').t('mergeDirectoryEmpty')),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byKey(const ValueKey('merge-directory-next')), findsNothing);
  });

  testWidgets(
    'replacing borrowed gateways clears the page and ignores an old read',
    (tester) async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await h.read(tester);
      final replacement = _DirectoryGateway();
      await tester.pumpWidget(h.widget(directory: replacement));
      h.directory.complete(_page());
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(replacement.pending, isEmpty);
      expect(h.directory.closed, isFalse);
    },
  );

  testWidgets('narrow dark large text keeps the native selector readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = await _Harness.start();
    addTearDown(h.close);
    await tester.pumpWidget(h.widget(large: true));
    await h.read(tester);
    h.directory.complete(_page());
    await tester.pumpAndSettle();
    await h.select(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(PersonalTargetMergeProjectionPanel), findsOneWidget);
  });
}

const _generation = '7f260000-0000-4000-8000-000000000001';
const _secondGeneration = '7f260000-0000-4000-8000-000000000002';

PersonalTargetMergeDirectory _page({String id = _generation, String? next}) =>
    PersonalTargetMergeDirectory(
      workspaceId: syntheticSessionContext.workspace.id,
      projectId: syntheticSessionContext.project.id,
      items: [
        PersonalTargetMergeDirectoryItem(
          generationId: id,
          targetType: PromotionTargetType.person,
          retainedTargetId: 'source-a',
          memberTargetIds: ['source-a', 'source-b'],
          reviewDueAtUtc: DateTime.utc(2027),
        ),
      ],
      nextCursor: next,
    );

final class _DirectoryGateway implements PersonalTargetMergeDirectoryGateway {
  final pending = <Completer<PersonalTargetMergeDirectoryResult>>[];
  final cursors = <String?>[];
  var closed = false;
  @override
  Future<PersonalTargetMergeDirectoryResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    String? afterGenerationId,
    required bool Function() requestIsCurrent,
  }) {
    cursors.add(afterGenerationId);
    final result = Completer<PersonalTargetMergeDirectoryResult>();
    pending.add(result);
    return result.future;
  }

  void complete(PersonalTargetMergeDirectory page) =>
      pending.last.complete(PersonalTargetMergeDirectoryReady(page));
  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _ProjectionGateway implements PersonalTargetMergeProjectionGateway {
  var calls = 0;
  var closed = false;
  @override
  Future<PersonalTargetMergeProjectionResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) async {
    calls++;
    return const PersonalTargetMergeProjectionRejected(
      PersonalTargetMergeProjectionFailure.serviceUnavailable,
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _Harness {
  _Harness(this.identity, this.contexts, this.session);
  final FakeIdentitySession identity;
  final FakeSessionContextGateway contexts;
  final AppSession session;
  final directory = _DirectoryGateway();
  final projection = _ProjectionGateway();
  static Future<_Harness> start() async {
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'owner',
          email: 'owner@example.test',
        ),
        expiresAt: DateTime.utc(2030),
      ),
    );
    final contexts = FakeSessionContextGateway(
      context: TrustedSessionContext(
        appUserId: syntheticSessionContext.appUserId,
        workspace: syntheticSessionContext.workspace,
        project: syntheticSessionContext.project,
        questionnaireVersion: syntheticSessionContext.questionnaireVersion,
        capabilities: {
          'view_assigned_target_pii',
          'manage_assigned_target_merges',
        },
      ),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: contexts,
    );
    await session.start();
    return _Harness(identity, contexts, session);
  }

  Widget widget({
    _DirectoryGateway? directory,
    bool large = false,
    String locale = 'zh',
  }) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF14746F),
        brightness: large ? Brightness.dark : Brightness.light,
      ),
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(large ? 2 : 1)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PersonalTargetMergeDirectoryPanel(
            text: AppStrings(locale),
            identitySession: identity,
            appSession: session,
            directoryGateway: directory ?? this.directory,
            projectionGateway: projection,
          ),
        ),
      ),
    ),
  );
  Future<void> read(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('merge-directory-read'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  Future<void> select(WidgetTester tester) async {
    final selector = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人 · $_generation').last);
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await session.close();
    await identity.close();
  }
}
