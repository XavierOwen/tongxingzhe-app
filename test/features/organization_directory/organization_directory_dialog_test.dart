import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_directory_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_invitation_create_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_membership_self_leave_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directed_account_invitation/organization_directed_account_invitation.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/organization_membership_self_leave/organization_membership_self_leave.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';

import '../../support/fake_runtime_values.dart';

void main() {
  testWidgets('打开只读一次，按原顺序显示可选名称与完整 UUID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);

    await _open(tester, fixture.session, gateway);

    expect(gateway.listCalls, 1);
    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data),
      [
        _organizationA.organizationName,
        _organizationA.organizationWorkspaceId,
        _organizationB.organizationName,
        _organizationB.organizationWorkspaceId,
      ],
    );
    for (final text in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      expect(text.maxLines, isNull);
    }
    expect(gateway.closed, isFalse);
  });

  testWidgets('初始读取允许关闭，防止重复刷新并忽略迟到结果', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, settle: false);

    expect(
      find.text(const AppStrings('zh').t('organizationDirectoryLoading')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
    expect(tester.widget<TextButton>(_close).onPressed, isNotNull);
    await tester.tap(_refresh, warnIfMissed: false);
    await tester.pump();
    expect(gateway.listCalls, 1);

    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationDirectoryDialog), findsNothing);
    expect(fixture.session.current.stage, AppSessionStage.ready);
    expect(gateway.closed, isFalse);

    pending.complete(OrganizationDirectorySuccess(const [_organizationA]));
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新先清除旧快照，失败不冒充空目录且可再试', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
      pending,
      OrganizationDirectorySuccess(const [_organizationB]),
    ]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);
    expect(find.text(_organizationA.organizationName), findsOneWidget);

    await tester.tap(_refresh);
    await tester.pump();
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(find.text(text.t('organizationDirectoryLoading')), findsOneWidget);
    await tester.tap(_refresh, warnIfMissed: false);
    expect(gateway.listCalls, 2);

    pending.complete(
      const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.networkUnavailable,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(text.t('organizationDirectoryNetworkUnavailable')),
      findsOneWidget,
    );
    expect(find.text(text.t('organizationDirectoryEmpty')), findsNothing);
    expect(find.text(_organizationA.organizationName), findsNothing);

    await tester.tap(_refresh);
    await tester.pumpAndSettle();
    expect(gateway.listCalls, 3);
    expect(find.text(_organizationB.organizationName), findsOneWidget);
  });

  testWidgets('成功空目录与失败状态分开', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationDirectorySuccess(const [])]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);

    expect(find.text(text.t('organizationDirectoryEmpty')), findsOneWidget);
    expect(
      find.text(text.t('organizationDirectoryInvalidResponse')),
      findsNothing,
    );
  });

  for (final code in OrganizationDirectoryFailureCode.values) {
    testWidgets('${code.name} 显示对应脱敏提示而不是空目录', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([OrganizationDirectoryRejected(code)]);
      const text = AppStrings('zh');
      await _open(tester, fixture.session, gateway);

      expect(find.text(_failureText(text, code)), findsOneWidget);
      expect(find.text(text.t('organizationDirectoryEmpty')), findsNothing);
      expect(find.byType(OrganizationDirectoryDialog), findsOneWidget);
    });
  }

  testWidgets('未知异常只显示 invalidResponse，不泄露原文', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([StateError('secret provider detail')]);
    const text = AppStrings('zh');
    await _open(tester, fixture.session, gateway);

    expect(
      find.text(text.t('organizationDirectoryInvalidResponse')),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('provider'), findsNothing);
  });

  testWidgets('会话不再 ready 时清空并永久禁用该窗口的读取', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, settle: false);

    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    expect(
      find.text(const AppStrings('zh').t('organizationDirectoryUnauthorized')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);

    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    expect(fixture.session.current.stage, AppSessionStage.ready);
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
    await tester.tap(_refresh, warnIfMissed: false);
    expect(gateway.listCalls, 1);

    pending.complete(OrganizationDirectorySuccess(const [_organizationA]));
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(
      find.text(const AppStrings('zh').t('organizationDirectoryUnauthorized')),
      findsOneWidget,
    );
  });

  testWidgets('换账号清除旧目录，同账号切换项目不重读', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
    ]);
    await _open(tester, fixture.session, gateway);

    await fixture.session.selectProject(_contextAOtherProject.project.id);
    await tester.pumpAndSettle();
    expect(fixture.session.current.context, _contextAOtherProject);
    expect(find.text(_organizationA.organizationName), findsOneWidget);
    expect(gateway.listCalls, 1);

    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    expect(fixture.session.current.context?.appUserId, _contextB.appUserId);
    expect(find.text(_organizationA.organizationName), findsNothing);
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
  });

  testWidgets('状态为 live region，按键关闭后焦点返回入口', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    await _pumpLauncher(tester, fixture.session, _Gateway());

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final status = find.byKey(const ValueKey('organization-directory-status'));
    expect(
      tester
          .getSemantics(status)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationDirectoryDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _launcher), isTrue);
    semantics.dispose();
  });

  testWidgets('中英文在窄屏 200% 字号、长内容与宽屏暗色下无 overflow', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final organizations = List.generate(
      12,
      (index) => OrganizationDirectoryEntry(
        organizationWorkspaceId:
            '123e4567-e89b-12d3-a456-${index.toString().padLeft(12, '0')}',
        organizationName:
            '很长的组织原始名称不应被省略 $index ${List.filled(20, '界').join()}',
      ),
    );
    await _open(
      tester,
      fixture.session,
      _Gateway([OrganizationDirectorySuccess(organizations)]),
      textScaler: TextScaler.linear(2),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(organizations.last.organizationName), findsOneWidget);
    expect(
      find.text(organizations.last.organizationWorkspaceId),
      findsOneWidget,
    );
    await tester.tap(_close);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1280, 900);
    await _open(
      tester,
      fixture.session,
      _Gateway([
        OrganizationDirectorySuccess(const [_organizationA]),
      ]),
      localeCode: 'en',
      themeMode: ThemeMode.dark,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text(const AppStrings('en').t('organizationDirectoryHelp')),
      findsOneWidget,
    );
  });

  testWidgets('关闭与刷新触控目标至少为 48 logical pixels', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    await _open(
      tester,
      fixture.session,
      _Gateway([
        OrganizationDirectorySuccess(const [_organizationA]),
      ]),
    );

    for (final target in [_close, _refresh]) {
      final rect = tester.getSemantics(target).rect;
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$target width');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$target height');
    }
    semantics.dispose();
  });

  testWidgets('选定的组织原样显示，取消不提交', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final leaveGateway = _SelfLeaveGateway();
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      selfLeaveGateway: leaveGateway,
    );

    final selectedLeave = find.byKey(
      ValueKey('organization-leave-${_organizationB.organizationWorkspaceId}'),
    );
    await tester.ensureVisible(selectedLeave);
    await tester.tap(selectedLeave);
    await tester.pumpAndSettle();

    final dialog = find.byType(OrganizationMembershipSelfLeaveDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(_organizationB.organizationWorkspaceId),
      ),
      findsOneWidget,
    );
    await tester.tap(_leaveCancel);
    await tester.pumpAndSettle();
    expect(leaveGateway.calls, isEmpty);
    expect(directoryGateway.listCalls, 1);
  });

  testWidgets('每个组织行创建邀请固定选中组织，不刷新目录且不猜 owner', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final invitationGateway = _InvitationGateway();
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      invitationGateway: invitationGateway,
    );

    final create = find.byKey(
      ValueKey(
        'organization-invitation-create-${_organizationB.organizationWorkspaceId}',
      ),
    );
    expect(create, findsOneWidget);
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    final dialog = find.byType(OrganizationInvitationCreateDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(_organizationB.organizationWorkspaceId),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(_organizationA.organizationWorkspaceId),
      ),
      findsNothing,
    );
    expect(directoryGateway.listCalls, 1);
    await tester.enterText(
      find.byKey(const ValueKey('organization-invitation-create-target-id')),
      _targetAppUserId,
    );
    await tester.tap(
      find.byKey(const ValueKey('organization-invitation-create-submit')),
    );
    await tester.pumpAndSettle();
    expect(
      invitationGateway.calls.single.organizationWorkspaceId,
      _organizationB.organizationWorkspaceId,
    );
    expect(directoryGateway.listCalls, 1);
    expect(invitationGateway.closed, isFalse);
  });

  testWidgets('成功时必须先删本地快照，再提交并以新目录为准', (tester) async {
    final local = await _LocalVault.seeded();
    final fixture = await _Fixture.create(
      offlinePiiVault: local.vault,
      initialContext: _organizationAContext,
    );
    local.store.deleteRequested = Completer<void>();
    local.store.releaseDelete = Completer<void>();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
      // Exact replay or a later rejoin can legitimately keep the entry visible.
      OrganizationDirectorySuccess(const [_organizationA]),
    ]);
    final leaveGateway = _SelfLeaveGateway([
      OrganizationMembershipSelfLeaveSuccess(_receipt),
    ]);
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      selfLeaveGateway: leaveGateway,
    );
    await tester.tap(
      find.byKey(
        ValueKey(
          'organization-leave-${_organizationA.organizationWorkspaceId}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_leaveConfirm);
    await tester.pump();
    await local.store.deleteRequested!.future;
    expect(leaveGateway.calls, isEmpty);
    expect(
      find.text(const AppStrings('zh').t('organizationLeaveClearing')),
      findsOneWidget,
    );

    local.store.releaseDelete!.complete();
    await tester.pumpAndSettle();
    expect(leaveGateway.calls, hasLength(1));
    expect(local.store.values, isEmpty);
    expect(directoryGateway.listCalls, 2);
    expect(find.text(_organizationA.organizationWorkspaceId), findsOneWidget);
    expect(
      find.text(const AppStrings('zh').t('organizationLeaveSuccess')),
      findsOneWidget,
    );
  });

  for (final failure in _LocalFailure.values) {
    testWidgets('本地 ${failure.name} 失败时零 HTTP，修复后可重试', (tester) async {
      final local = await _LocalVault.seeded();
      final fixture = await _Fixture.create(
        offlinePiiVault: local.vault,
        initialContext: _organizationAContext,
      );
      switch (failure) {
        case _LocalFailure.read:
          local.store.failRead = true;
        case _LocalFailure.delete:
          local.store.failDelete = true;
      }
      addTearDown(fixture.close);
      final leaveGateway = _SelfLeaveGateway([
        const OrganizationMembershipSelfLeaveRejected(
          OrganizationMembershipSelfLeaveFailureCode.forbidden,
        ),
      ]);
      var generatedIds = 0;
      await _openSelfLeave(
        tester,
        fixture.session,
        leaveGateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return _requestIdA;
        },
      );

      await tester.tap(_leaveConfirm);
      await tester.pumpAndSettle();
      expect(leaveGateway.calls, isEmpty);
      expect(generatedIds, 1);
      expect(
        find.text(const AppStrings('zh').t('organizationLeaveCleanupFailed')),
        findsOneWidget,
      );

      local.store
        ..failRead = false
        ..failDelete = false;
      await tester.tap(_leaveConfirm);
      await tester.pumpAndSettle();
      expect(leaveGateway.calls.single.requestId, _requestIdA);
      expect(generatedIds, 1);
    });
  }

  for (final code in OrganizationMembershipSelfLeaveFailureCode.values) {
    testWidgets('${code.name} 显示对应脱敏退出提示', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final leaveGateway = _SelfLeaveGateway([
        OrganizationMembershipSelfLeaveRejected(code),
      ]);
      const text = AppStrings('zh');
      await _openSelfLeave(tester, fixture.session, leaveGateway);

      await tester.tap(_leaveConfirm);
      await tester.pumpAndSettle();
      expect(
        find.text(text.t('organizationLeaveFailure.${code.name}')),
        findsOneWidget,
      );
      expect(leaveGateway.calls, hasLength(1));
    });
  }

  for (final code in const [
    OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
    OrganizationMembershipSelfLeaveFailureCode.serviceUnavailable,
    OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
  ]) {
    testWidgets('${code.name} 不自动重试且同窗口复用 UUID', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final leaveGateway = _SelfLeaveGateway([
        OrganizationMembershipSelfLeaveRejected(code),
        OrganizationMembershipSelfLeaveRejected(code),
      ]);
      var generatedIds = 0;
      await _openSelfLeave(
        tester,
        fixture.session,
        leaveGateway,
        requestIdGenerator: () {
          generatedIds += 1;
          return _requestIdA;
        },
      );

      await tester.tap(_leaveConfirm);
      await tester.pumpAndSettle();
      expect(leaveGateway.calls, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
      expect(leaveGateway.calls, hasLength(1));
      expect(
        find.text(const AppStrings('zh').t('organizationLeaveUncertain')),
        findsOneWidget,
      );

      await tester.tap(_leaveConfirm);
      await tester.pumpAndSettle();
      expect(leaveGateway.calls.map((call) => call.requestId), [
        _requestIdA,
        _requestIdA,
      ]);
      expect(generatedIds, 1);
    });
  }

  testWidgets('未知结果关闭需二次确认，重开后只在再确认时产生新 UUID', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final leaveGateway = _SelfLeaveGateway(const [
      OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
      ),
      OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
      ),
    ]);
    var generatedIds = 0;
    String generateId() => [_requestIdA, _requestIdB][generatedIds++];
    await _openSelfLeave(
      tester,
      fixture.session,
      leaveGateway,
      requestIdGenerator: generateId,
    );
    await tester.tap(_leaveConfirm);
    await tester.pumpAndSettle();

    await tester.tap(_leaveCancel);
    await tester.pumpAndSettle();
    expect(
      find.text(const AppStrings('zh').t('organizationLeaveDiscardTitle')),
      findsOneWidget,
    );
    expect(find.byType(OrganizationMembershipSelfLeaveDialog), findsOneWidget);
    await tester.tap(_leaveDiscard);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationMembershipSelfLeaveDialog), findsNothing);

    await tester.tap(_selfLeaveLauncher);
    await tester.pumpAndSettle();
    expect(generatedIds, 1);
    expect(leaveGateway.calls, hasLength(1));
    await tester.tap(_leaveConfirm);
    await tester.pumpAndSettle();
    expect(generatedIds, 2);
    expect(leaveGateway.calls.map((call) => call.requestId), [
      _requestIdA,
      _requestIdB,
    ]);
  });

  testWidgets('提交未完成时禁用重复确认和关闭', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationMembershipSelfLeaveResult>();
    final leaveGateway = _SelfLeaveGateway([pending]);
    await _openSelfLeave(tester, fixture.session, leaveGateway);

    await tester.tap(_leaveConfirm);
    await tester.pump();
    expect(leaveGateway.calls, hasLength(1));
    expect(tester.widget<FilledButton>(_leaveConfirm).onPressed, isNull);
    expect(tester.widget<TextButton>(_leaveCancel).onPressed, isNull);
    await tester.tap(_leaveConfirm, warnIfMissed: false);
    await tester.tap(_leaveCancel, warnIfMissed: false);
    await tester.pump();
    expect(leaveGateway.calls, hasLength(1));
    expect(find.byType(OrganizationMembershipSelfLeaveDialog), findsOneWidget);

    pending.complete(
      const OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.forbidden,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('清缓存期间换账号时不发 HTTP', (tester) async {
    final local = await _LocalVault.seeded();
    final fixture = await _Fixture.create(
      offlinePiiVault: local.vault,
      initialContext: _organizationAContext,
    );
    local.store.deleteRequested = Completer<void>();
    local.store.releaseDelete = Completer<void>();
    addTearDown(fixture.close);
    final leaveGateway = _SelfLeaveGateway();
    await _openSelfLeave(tester, fixture.session, leaveGateway);
    await tester.tap(_leaveConfirm);
    await tester.pump();
    await local.store.deleteRequested!.future;

    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pump();
    local.store.releaseDelete!.complete();
    await tester.pumpAndSettle();

    expect(leaveGateway.calls, isEmpty);
    expect(
      find.text(const AppStrings('zh').t('organizationLeaveUnauthorized')),
      findsOneWidget,
    );
  });

  testWidgets('提交期间换账号忽略迟到成功，不刷新旧目录', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
    ]);
    final pending = Completer<OrganizationMembershipSelfLeaveResult>();
    final leaveGateway = _SelfLeaveGateway([pending]);
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      selfLeaveGateway: leaveGateway,
    );
    await tester.tap(
      find.byKey(
        ValueKey(
          'organization-leave-${_organizationA.organizationWorkspaceId}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_leaveConfirm);
    await tester.pump();
    expect(leaveGateway.calls, hasLength(1));

    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    pending.complete(OrganizationMembershipSelfLeaveSuccess(_receipt));
    await tester.pumpAndSettle();

    expect(directoryGateway.listCalls, 1);
    expect(
      find.text(const AppStrings('zh').t('organizationLeaveSuccess')),
      findsNothing,
    );
    expect(find.byType(OrganizationMembershipSelfLeaveDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('销毁对话框后忽略迟到结果', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationMembershipSelfLeaveResult>();
    final leaveGateway = _SelfLeaveGateway([pending]);
    await _openSelfLeave(tester, fixture.session, leaveGateway);
    await tester.tap(_leaveConfirm);
    await tester.pump();
    expect(leaveGateway.calls, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(OrganizationMembershipSelfLeaveSuccess(_receipt));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('状态为 live region，键盘关闭后焦点返回入口', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    final leaveGateway = _SelfLeaveGateway(const [
      OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.forbidden,
      ),
    ]);
    await _pumpSelfLeaveLauncher(tester, fixture.session, leaveGateway);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(_leaveConfirm);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(_leaveStatus)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationMembershipSelfLeaveDialog), findsNothing);
    expect(_hasPrimaryFocus(tester, _selfLeaveLauncher), isTrue);
    semantics.dispose();
  });

  testWidgets('窄屏 200% 长名下 unknown 关键状态首屏可见', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    _useNarrowLargeText(tester);
    final leaveGateway = _SelfLeaveGateway(const [
      OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
      ),
    ]);
    const text = AppStrings('zh');
    await _openSelfLeave(
      tester,
      fixture.session,
      leaveGateway,
      organization: _longOrganization,
      textScaler: TextScaler.linear(2),
    );

    await tester.tap(_leaveConfirm);
    await tester.pumpAndSettle();

    _expectCriticalLeaveStateVisible(tester, text);
  });

  testWidgets('提交前已滚到底部时，unknown 到达后回到关键状态', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    _useNarrowLargeText(tester);
    final pending = Completer<OrganizationMembershipSelfLeaveResult>();
    final leaveGateway = _SelfLeaveGateway([pending]);
    const text = AppStrings('zh');
    await _openSelfLeave(
      tester,
      fixture.session,
      leaveGateway,
      organization: _longOrganization,
      textScaler: TextScaler.linear(2),
    );
    final contentScroll = find.descendant(
      of: find.byType(OrganizationMembershipSelfLeaveDialog),
      matching: find.byType(SingleChildScrollView),
    );
    expect(contentScroll, findsOneWidget);
    await tester.drag(contentScroll, const Offset(0, -3000));
    await tester.pumpAndSettle();

    await tester.tap(_leaveConfirm);
    await tester.pump();
    expect(leaveGateway.calls, hasLength(1));
    pending.complete(
      const OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
      ),
    );
    await tester.pumpAndSettle();

    _expectCriticalLeaveStateVisible(tester, text);
  });

  testWidgets('退出对话框在窄屏 200% 长名和英文宽屏暗色下无 overflow', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final longOrganization = OrganizationDirectoryEntry(
      organizationWorkspaceId: _organizationA.organizationWorkspaceId,
      organizationName: '很长的组织原始名称 ${List.filled(60, '界').join()}',
    );
    await _openSelfLeave(
      tester,
      fixture.session,
      _SelfLeaveGateway(),
      organization: longOrganization,
      textScaler: TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(longOrganization.organizationName), findsOneWidget);
    expect(find.text(longOrganization.organizationWorkspaceId), findsOneWidget);
    for (final target in [_leaveCancel, _leaveConfirm]) {
      final rect = tester.getSemantics(target).rect;
      expect(rect.width, greaterThanOrEqualTo(48), reason: '$target width');
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$target height');
    }
    await tester.tap(_leaveCancel);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1280, 900);
    await _pumpSelfLeaveLauncher(
      tester,
      fixture.session,
      _SelfLeaveGateway(),
      localeCode: 'en',
      themeMode: ThemeMode.dark,
    );
    await tester.tap(_selfLeaveLauncher);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text(const AppStrings('en').t('organizationLeaveHelp')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}

void _useNarrowLargeText(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void _expectCriticalLeaveStateVisible(WidgetTester tester, AppStrings text) {
  final dialogTop = tester
      .getRect(find.byType(OrganizationMembershipSelfLeaveDialog))
      .top;
  final actionsTop = tester.getRect(_leaveConfirm).top;
  final failure = find.text(
    text.t('organizationLeaveFailure.networkUnavailable'),
  );
  final uncertain = find.text(text.t('organizationLeaveUncertain'));
  for (final message in [uncertain, failure]) {
    final rect = tester.getRect(message);
    expect(rect.top, lessThan(actionsTop), reason: '$message below actions');
    expect(rect.bottom, greaterThan(dialogTop), reason: '$message above view');
  }
  expect(
    tester.getRect(uncertain).top,
    lessThan(tester.getRect(find.text(_longOrganization.organizationName)).top),
  );
}

final _launcher = find.byKey(const ValueKey('open-organization-directory'));
final _refresh = find.byKey(const ValueKey('organization-directory-refresh'));
final _close = find.byKey(const ValueKey('organization-directory-close'));
final _selfLeaveLauncher = find.byKey(
  const ValueKey('open-organization-self-leave'),
);
final _leaveCancel = find.byKey(const ValueKey('organization-leave-cancel'));
final _leaveConfirm = find.byKey(const ValueKey('organization-leave-confirm'));
final _leaveDiscard = find.byKey(const ValueKey('organization-leave-discard'));
final _leaveStatus = find.byKey(const ValueKey('organization-leave-status'));

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectoryGateway gateway, {
  bool settle = true,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  OrganizationMembershipSelfLeaveGateway selfLeaveGateway =
      const DeferredOrganizationMembershipSelfLeaveGateway(),
  OrganizationDirectedAccountInvitationGateway invitationGateway =
      const DeferredOrganizationDirectedAccountInvitationGateway(),
}) async {
  await _pumpLauncher(
    tester,
    session,
    gateway,
    localeCode: localeCode,
    textScaler: textScaler,
    themeMode: themeMode,
    selfLeaveGateway: selfLeaveGateway,
    invitationGateway: invitationGateway,
  );
  await tester.tap(_launcher);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  AppSession session,
  OrganizationDirectoryGateway gateway, {
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  OrganizationMembershipSelfLeaveGateway selfLeaveGateway =
      const DeferredOrganizationMembershipSelfLeaveGateway(),
  OrganizationDirectedAccountInvitationGateway invitationGateway =
      const DeferredOrganizationDirectedAccountInvitationGateway(),
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(useMaterial3: true),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    themeMode: themeMode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-organization-directory'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => OrganizationDirectoryDialog(
                text: AppStrings(localeCode),
                gateway: gateway,
                appSession: session,
                selfLeaveGateway: selfLeaveGateway,
                invitationGateway: invitationGateway,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _openSelfLeave(
  WidgetTester tester,
  AppSession session,
  OrganizationMembershipSelfLeaveGateway gateway, {
  OrganizationDirectoryEntry organization = _organizationA,
  String Function() requestIdGenerator = _defaultRequestId,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await _pumpSelfLeaveLauncher(
    tester,
    session,
    gateway,
    organization: organization,
    requestIdGenerator: requestIdGenerator,
    localeCode: localeCode,
    textScaler: textScaler,
    themeMode: themeMode,
  );
  await tester.tap(_selfLeaveLauncher);
  await tester.pumpAndSettle();
}

Future<void> _pumpSelfLeaveLauncher(
  WidgetTester tester,
  AppSession session,
  OrganizationMembershipSelfLeaveGateway gateway, {
  OrganizationDirectoryEntry organization = _organizationA,
  String Function() requestIdGenerator = _defaultRequestId,
  String localeCode = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(useMaterial3: true),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    themeMode: themeMode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-organization-self-leave'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => OrganizationMembershipSelfLeaveDialog(
                text: AppStrings(localeCode),
                organization: organization,
                gateway: gateway,
                appSession: session,
                requestIdGenerator: requestIdGenerator,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

String _defaultRequestId() => _requestIdA;

bool _hasPrimaryFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  if (identical(focused, target)) return true;
  var contains = false;
  focused.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      contains = true;
      return false;
    }
    return true;
  });
  return contains;
}

String _failureText(AppStrings text, OrganizationDirectoryFailureCode code) =>
    switch (code) {
      OrganizationDirectoryFailureCode.notConfigured => text.t(
        'organizationDirectoryNotConfigured',
      ),
      OrganizationDirectoryFailureCode.unauthorized => text.t(
        'organizationDirectoryUnauthorized',
      ),
      OrganizationDirectoryFailureCode.invalidRequest => text.t(
        'organizationDirectoryInvalidRequest',
      ),
      OrganizationDirectoryFailureCode.forbidden => text.t(
        'organizationDirectoryForbidden',
      ),
      OrganizationDirectoryFailureCode.serviceUnavailable => text.t(
        'organizationDirectoryServiceUnavailable',
      ),
      OrganizationDirectoryFailureCode.networkUnavailable => text.t(
        'organizationDirectoryNetworkUnavailable',
      ),
      OrganizationDirectoryFailureCode.invalidResponse => text.t(
        'organizationDirectoryInvalidResponse',
      ),
    };

final class _Fixture {
  _Fixture(this.identity, this.session);

  final _IdentitySession identity;
  final AppSession session;

  static Future<_Fixture> create({
    OfflinePiiVault? offlinePiiVault,
    TrustedSessionContext initialContext = _contextA,
  }) async {
    final identity = _IdentitySession(_signedIn('subject-a'));
    final session = AppSession(
      identitySession: identity,
      contextGateway: _ContextGateway(contextA: initialContext),
      offlinePiiVault: offlinePiiVault,
    );
    await session.start();
    return _Fixture(identity, session);
  }

  Future<void> close() async {
    await session.close();
    await identity.close();
  }
}

final class _IdentitySession implements IdentitySession {
  _IdentitySession(this._current);

  final _changes = StreamController<IdentitySnapshot>.broadcast();
  IdentitySnapshot _current;

  void emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  @override
  Future<IdentityResult<IdentitySnapshot>> restore() async =>
      IdentitySuccess(_current);

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async => IdentitySuccess(
    IdentityAccessToken(
      value: _current.principal!.externalSubject,
      expiresAt: _current.expiresAt,
    ),
  );

  @override
  Future<void> close() => _changes.close();

  @override
  Future<IdentityResult<IdentitySnapshot>> signOut() async {
    const snapshot = IdentitySnapshot.signedOut();
    emit(snapshot);
    return const IdentitySuccess(snapshot);
  }

  @override
  Future<IdentityResult<IdentitySnapshot>> refresh() async =>
      IdentitySuccess(_current);

  @override
  Future<IdentityResult<IdentitySnapshot>> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> signUp({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmSignUpOtp({
    required String email,
    required String otp,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> requestPasswordRecovery({
    required String email,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> confirmPasswordRecoveryOtp({
    required String email,
    required String otp,
  }) => throw UnimplementedError();

  @override
  Future<IdentityResult<IdentitySnapshot>> updateRecoveredPassword({
    required String newPassword,
  }) => throw UnimplementedError();
}

final class _ContextGateway implements SessionContextGateway {
  const _ContextGateway({this.contextA = _contextA});

  final TrustedSessionContext contextA;

  @override
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken) async =>
      SessionContextSuccess(
        accessToken.value == 'subject-b' ? _contextB : contextA,
      );

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async => SessionContextSuccess(_contextAOtherProject);

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.serverRejected);

  @override
  Future<void> close() async {}
}

final class _Gateway implements OrganizationDirectoryGateway {
  _Gateway([Iterable<Object> results = const []])
    : _results = Queue.of(results);

  final Queue<Object> _results;
  var listCalls = 0;
  var closed = false;

  @override
  Future<OrganizationDirectoryResult> list() async {
    listCalls += 1;
    if (_results.isEmpty) {
      return const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.notConfigured,
      );
    }
    final next = _results.removeFirst();
    if (next is Completer<OrganizationDirectoryResult>) return next.future;
    if (next is OrganizationDirectoryResult) return next;
    throw next;
  }

  @override
  Future<void> close() async => closed = true;
}

typedef _InvitationCall = ({
  String invitationId,
  String organizationWorkspaceId,
  String targetAppUserId,
});

final class _InvitationGateway
    implements OrganizationDirectedAccountInvitationGateway {
  final calls = <_InvitationCall>[];
  var closed = false;

  @override
  Future<OrganizationDirectedAccountInvitationCreateResult> create({
    required String invitationId,
    required String organizationWorkspaceId,
    required String targetAppUserId,
  }) async {
    calls.add((
      invitationId: invitationId,
      organizationWorkspaceId: organizationWorkspaceId,
      targetAppUserId: targetAppUserId,
    ));
    return const OrganizationDirectedAccountInvitationCreateRejected(
      OrganizationDirectedAccountInvitationFailureCode.notConfigured,
    );
  }

  @override
  Future<OrganizationDirectedAccountInvitationPreviewResult> preview({
    required String invitationId,
  }) => throw UnsupportedError('unused directory wiring preview');

  @override
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  }) => throw UnsupportedError('unused directory wiring accept');

  @override
  Future<void> close() async => closed = true;
}

typedef _LeaveCall = ({String requestId, String organizationWorkspaceId});

final class _SelfLeaveGateway
    implements OrganizationMembershipSelfLeaveGateway {
  _SelfLeaveGateway([Iterable<Object> results = const []])
    : _results = Queue.of(results);

  final Queue<Object> _results;
  final calls = <_LeaveCall>[];

  @override
  Future<OrganizationMembershipSelfLeaveResult> leave({
    required String requestId,
    required String organizationWorkspaceId,
  }) async {
    calls.add((
      requestId: requestId,
      organizationWorkspaceId: organizationWorkspaceId,
    ));
    if (_results.isEmpty) {
      return const OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.notConfigured,
      );
    }
    final next = _results.removeFirst();
    if (next is Completer<OrganizationMembershipSelfLeaveResult>) {
      return next.future;
    }
    if (next is OrganizationMembershipSelfLeaveResult) return next;
    throw next;
  }

  @override
  Future<void> close() async {}
}

enum _LocalFailure { read, delete }

final class _LocalVault {
  const _LocalVault(this.vault, this.store);

  final OfflinePiiVault vault;
  final _MemorySecureValueStore store;

  static Future<_LocalVault> seeded() async {
    final store = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: store,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 9, 7, 12)),
      installationId: 'test-installation',
    );
    expect(
      await vault.replace(
        externalSubject: 'subject-a',
        context: _organizationAContext,
        assignedTargets: const [],
        authorizedAtUtc: DateTime.utc(2026, 9, 7, 11),
      ),
      isA<OfflinePiiSaved>(),
    );
    return _LocalVault(vault, store);
  }
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  var failRead = false;
  var failDelete = false;
  Completer<void>? deleteRequested;
  Completer<void>? releaseDelete;

  @override
  Future<void> delete(String key) async {
    final requested = deleteRequested;
    if (requested != null && !requested.isCompleted) requested.complete();
    await releaseDelete?.future;
    if (failDelete) throw StateError('synthetic delete failure');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('synthetic read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _MemoryOfflinePiiLockStore implements OfflinePiiLockStore {
  final locks = <String, OfflinePiiLock>{};

  @override
  Future<void> clear(String scopeKey) async => locks.remove(scopeKey);

  @override
  Future<OfflinePiiLock?> read(String scopeKey) async => locks[scopeKey];

  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async {
    locks[scopeKey] = lock;
  }
}

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030, subject == 'subject-a' ? 1 : 2),
);

const _organizationA = OrganizationDirectoryEntry(
  organizationWorkspaceId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  organizationName: '  同名组织  ',
);
const _organizationB = OrganizationDirectoryEntry(
  organizationWorkspaceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  organizationName: '  同名组织  ',
);

final _longOrganization = OrganizationDirectoryEntry(
  organizationWorkspaceId: _organizationA.organizationWorkspaceId,
  organizationName: '很长的组织原始名称 ${List.filled(60, '界').join()}',
);

const _requestIdA = 'c1111111-1111-4111-8111-111111111111';
const _requestIdB = 'c2222222-2222-4222-8222-222222222222';
const _targetAppUserId = '99999999-9999-4999-8999-999999999999';

final _receipt = OrganizationMembershipSelfLeaveReceipt(
  membershipSelfLeaveContractId: 'organization-membership-self-leave:v1',
  organizationWorkspaceId: _organizationA.organizationWorkspaceId,
  organizationMembershipId: 'd1111111-1111-4111-8111-111111111111',
  effectiveAtUtc: DateTime.utc(2026, 9, 7, 12),
);

const _organizationAContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    kind: WorkspaceKind.organization,
    name: '组织空间',
  ),
  project: ProjectContext(
    id: '31111111-1111-4111-8111-111111111119',
    name: '组织项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '41111111-1111-4111-8111-111111111119',
    versionNumber: 1,
  ),
  capabilities: {'view_assigned_target_pii'},
);

const _contextA = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '21111111-1111-4111-8111-111111111111',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '31111111-1111-4111-8111-111111111111',
    name: '项目甲',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '41111111-1111-4111-8111-111111111111',
    versionNumber: 1,
  ),
  capabilities: {},
);

const _contextAOtherProject = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '21111111-1111-4111-8111-111111111111',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '31111111-1111-4111-8111-111111111112',
    name: '项目丙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '41111111-1111-4111-8111-111111111112',
    versionNumber: 2,
  ),
  capabilities: {},
);

const _contextB = TrustedSessionContext(
  appUserId: '12222222-2222-4222-8222-222222222222',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.organization,
    name: '组织空间',
  ),
  project: ProjectContext(
    id: '32222222-2222-4222-8222-222222222222',
    name: '项目乙',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '42222222-2222-4222-8222-222222222222',
    versionNumber: 2,
  ),
  capabilities: {},
);
