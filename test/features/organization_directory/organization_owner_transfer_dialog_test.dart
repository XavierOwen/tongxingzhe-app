import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_owner_transfer_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/organization_owner_transfer/organization_owner_transfer.dart';

void main() {
  testWidgets('首次实际提交才生成 request，重试保留完整 tuple 且不能编辑', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    var generated = 0;
    final gateway = _Gateway([
      const OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.networkUnavailable,
      ),
      OrganizationOwnerTransferSuccess(_receipt),
    ]);
    await _open(
      tester,
      fixture.session,
      gateway,
      requestIdGenerator: () {
        generated += 1;
        return _requestId.toUpperCase();
      },
    );
    await tester.enterText(_field, _targetMembershipId);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    expect(generated, 0);
    await tester.tap(_edit);
    await tester.pumpAndSettle();
    await tester.tap(_review);
    await tester.pumpAndSettle();
    expect(generated, 0);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(generated, 1);
    expect(_field, findsNothing);
    expect(_edit, findsNothing);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(generated, 1);
    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.toSet(), {
      (
        requestId: _requestId,
        targetOrganizationMembershipId: _targetMembershipId,
        organizationWorkspaceId: _organizationId,
      ),
    });
  });

  for (final throws in [false, true]) {
    testWidgets('非法或抛错 generator 无 pending intent，仍可编辑 target：$throws', (
      tester,
    ) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      var generated = 0;
      final gateway = _Gateway([OrganizationOwnerTransferSuccess(_receipt)]);
      await _open(
        tester,
        fixture.session,
        gateway,
        requestIdGenerator: () {
          generated += 1;
          if (generated == 1) {
            if (throws) throw StateError('secret generator detail');
            return 'not-a-uuid';
          }
          return _requestId;
        },
      );
      await tester.enterText(_field, _targetMembershipId);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
      expect(_edit, findsOneWidget);
      expect(_uncertain, findsNothing);
      expect(find.textContaining('secret'), findsNothing);
      await tester.tap(_edit);
      await tester.pumpAndSettle();
      const revisedTarget = '77777777-7777-4777-8777-777777777777';
      await tester.enterText(_field, revisedTarget);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(generated, 2);
      expect(
        gateway.calls.single.targetOrganizationMembershipId,
        revisedTarget,
      );
      expect(gateway.calls.single.requestId, _requestId);
    });
  }

  testWidgets('输入到确认恢复 Escape 焦点；未提交直接关闭不生成 request', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    var generated = 0;
    final gateway = _Gateway([]);
    await _open(
      tester,
      fixture.session,
      gateway,
      requestIdGenerator: () {
        generated += 1;
        return _requestId;
      },
    );
    await tester.enterText(_field, _targetMembershipId);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(generated, 0);
    expect(gateway.calls, isEmpty);
  });

  testWidgets('稳定 targetAlreadyOwner 结束前次不确定，关闭不再要求丢弃', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.invalidResponse,
      ),
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.targetAlreadyOwner,
      ),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    expect(_uncertain, findsOneWidget);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(_uncertain, findsNothing);
    expect(_edit, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(_discard, findsNothing);
    expect(gateway.calls.toSet(), hasLength(1));
  });

  testWidgets('本地规范 UUID 后单独确认，成功留窗显示完整交接回执', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationOwnerTransferSuccess(_receipt)]);
    final clipboardWrites = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, '  ${_targetMembershipId.toUpperCase()}  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(gateway.calls, isEmpty);
    expect(_field, findsNothing);
    expect(_edit, findsOneWidget);
    expect(find.text(_targetMembershipId), findsOneWidget);
    await tester.tap(_edit);
    await tester.pumpAndSettle();
    expect(_field, findsOneWidget);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(gateway.calls, [
      (
        requestId: _requestId,
        targetOrganizationMembershipId: _targetMembershipId,
        organizationWorkspaceId: _organizationId,
      ),
    ]);
    for (final value in [
      _organization.organizationName,
      _targetMembershipId,
      _receipt.organizationWorkspaceId,
      _receipt.ownerTransferContractId,
      _receipt.previousOwnerAssignmentId,
      _receipt.organizationOwnerAssignmentId,
      _receipt.effectiveAtUtc.toUtc().toIso8601String(),
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(_dialog, findsOneWidget);
    expect(_submit, findsNothing);
    expect(clipboardWrites, isEmpty);
    expect(gateway.closed, isFalse);
    expect(fixture.context.selectCalls, 0);
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(gateway.closed, isFalse);
  });

  testWidgets('非法 UUID 和 URL 不触网；输入 Enter 只进入确认', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([]);
    await _open(tester, fixture.session, gateway);
    for (final invalid in [
      '',
      'not-a-uuid',
      'https://example.test/$_targetMembershipId',
    ]) {
      await tester.enterText(_field, invalid);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text(
          const AppStrings(
            'zh',
          ).t('organizationOwnerTransferInvalidTargetMembership'),
        ),
        findsOneWidget,
      );
      expect(_submit, findsNothing);
    }
    await tester.enterText(_field, _targetMembershipId);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_submit, findsOneWidget);
    expect(gateway.calls, isEmpty);
  });

  for (final code in OrganizationOwnerTransferFailureCode.values) {
    testWidgets('${code.name} 使用稳定提示，且只指定三类失败不确定', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([OrganizationOwnerTransferRejected(code)]);
      await _confirmAndSubmit(tester, fixture.session, gateway);
      final uncertain = [
        OrganizationOwnerTransferFailureCode.networkUnavailable,
        OrganizationOwnerTransferFailureCode.serviceUnavailable,
        OrganizationOwnerTransferFailureCode.invalidResponse,
      ].contains(code);
      expect(_uncertain, uncertain ? findsOneWidget : findsNothing);
      expect(_edit, findsNothing);
      expect(_field, findsNothing);
      if (code == OrganizationOwnerTransferFailureCode.unauthorized) {
        expect(find.text(_targetMembershipId), findsNothing);
        expect(find.text(_organization.organizationName), findsNothing);
        expect(find.text(_organizationId), findsNothing);
        expect(_submit, findsNothing);
        expect(
          find.text(
            const AppStrings('zh').t('organizationOwnerTransferUnauthorized'),
          ),
          findsOneWidget,
        );
      } else {
        expect(
          find.text(
            const AppStrings(
              'zh',
            ).t('organizationOwnerTransferFailure.${code.name}'),
          ),
          findsOneWidget,
        );
        expect(_submit, findsOneWidget);
      }
    });
  }

  testWidgets('throw 不显示原文；Escape 请求保留或丢弃同一重试意图', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      StateError('secret provider detail'),
      OrganizationOwnerTransferSuccess(_receipt),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    expect(find.textContaining('secret'), findsNothing);
    expect(_uncertain, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_keepRetry, findsOneWidget);
    expect(_discard, findsOneWidget);
    for (final action in [_keepRetry, _discard]) {
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      var reachable = false;
      for (var i = 0; i < 6; i += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        reachable = reachable || _hasFocus(tester, action);
      }
      expect(reachable, isTrue);
    }
    await tester.tap(_keepRetry);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(gateway.calls, hasLength(2));
    expect(gateway.calls.toSet(), {
      (
        requestId: _requestId,
        targetOrganizationMembershipId: _targetMembershipId,
        organizationWorkspaceId: _organizationId,
      ),
    });
    expect(_uncertain, findsNothing);
  });

  testWidgets('不确定到稳定 conflict 清除不确定性，仍锁定相同 intent', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.networkUnavailable,
      ),
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.conflict,
      ),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    expect(_uncertain, findsOneWidget);
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(_uncertain, findsNothing);
    expect(_edit, findsNothing);
    expect(gateway.calls.toSet(), {
      (
        requestId: _requestId,
        targetOrganizationMembershipId: _targetMembershipId,
        organizationWorkspaceId: _organizationId,
      ),
    });
    await tester.tap(_close);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(_discard, findsNothing);
  });

  testWidgets('系统返回也要求丢弃确认，明确丢弃后关闭', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway(const [
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.serviceUnavailable,
      ),
    ]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(_discard, findsOneWidget);
    await tester.tap(_discard);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(gateway.calls, hasLength(1));
    expect(gateway.closed, isFalse);
  });

  testWidgets('busy 阻止重复调用、关闭、Escape 与系统返回', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationOwnerTransferResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, _targetMembershipId);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    final submit = tester.widget<FilledButton>(_submit).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(gateway.calls, hasLength(1));
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    expect(tester.widget<TextButton>(_close).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(_discard, findsNothing);
    pending.complete(OrganizationOwnerTransferSuccess(_receipt));
    await tester.pumpAndSettle();
    expect(find.text(_receipt.organizationOwnerAssignmentId), findsOneWidget);
  });

  testWidgets('同账号项目变化保留交接；捕获组织不随 widget 更新改变', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final organizations = ValueNotifier(_organization);
    addTearDown(organizations.dispose);
    final gateway = _Gateway(const [
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.forbidden,
      ),
      OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.forbidden,
      ),
    ]);
    await _open(tester, fixture.session, gateway, organizations: organizations);
    await tester.enterText(_field, _targetMembershipId);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    expect(
      await fixture.session.selectProject('project-b'),
      isA<SessionContextSuccess>(),
    );
    organizations.value = const OrganizationDirectoryEntry(
      organizationWorkspaceId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      organizationName: '另一个组织',
    );
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(gateway.calls.toSet(), {
      (
        requestId: _requestId,
        targetOrganizationMembershipId: _targetMembershipId,
        organizationWorkspaceId: _organizationId,
      ),
    });
    expect(find.text('另一个组织'), findsNothing);
  });

  testWidgets('同一登录 token 刷新保留进行中的交接意图与回执', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationOwnerTransferResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, _targetMembershipId);
    await tester.tap(_review);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pump();

    final identity = fixture.identity.current;
    fixture.identity.emit(
      IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: identity.principal,
        expiresAt: identity.expiresAt!.add(const Duration(hours: 1)),
      ),
    );
    await tester.pump();
    expect(find.text(_targetMembershipId), findsOneWidget);
    expect(_submit, findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    pending.complete(OrganizationOwnerTransferSuccess(_receipt));
    await tester.pumpAndSettle();

    expect(find.text(_receipt.organizationOwnerAssignmentId), findsOneWidget);
    expect(gateway.calls, [
      (
        requestId: _requestId,
        organizationWorkspaceId: _organizationId,
        targetOrganizationMembershipId: _targetMembershipId,
      ),
    ]);
    expect(fixture.context.selectCalls, 0);
    expect(gateway.closed, isFalse);
  });

  for (final aba in [false, true]) {
    testWidgets('${aba ? 'ABA' : '切账号'} 清空敏感状态并隔离迟到交接回执', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final pending = Completer<OrganizationOwnerTransferResult>();
      final gateway = _Gateway([pending]);
      await _open(tester, fixture.session, gateway);
      await tester.enterText(_field, _targetMembershipId);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pump();
      fixture.identity.emit(_signedIn('subject-b'));
      await tester.pumpAndSettle();
      if (aba) {
        fixture.identity.emit(_signedIn('subject-a'));
        await tester.pumpAndSettle();
      }
      pending.complete(OrganizationOwnerTransferSuccess(_receipt));
      await tester.pumpAndSettle();
      for (final value in [
        _targetMembershipId,
        _organizationId,
        _organization.organizationName,
        _receipt.organizationOwnerAssignmentId,
      ]) {
        expect(find.text(value), findsNothing);
      }
      expect(_submit, findsNothing);
      expect(_uncertain, findsNothing);
      expect(
        find.text(
          const AppStrings('zh').t('organizationOwnerTransferUnauthorized'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('注销清空已成功回执与本地输入，不能在重新登录后恢复', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationOwnerTransferSuccess(_receipt)]);
    await _confirmAndSubmit(tester, fixture.session, gateway);
    fixture.identity.emit(const IdentitySnapshot.signedOut());
    await tester.pumpAndSettle();
    fixture.identity.emit(_signedIn('subject-a'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(_field, findsNothing);
    expect(_submit, findsNothing);
  });

  testWidgets('Tab 可达核对按钮且各动作触控目标至少 48 logical pixels', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([OrganizationOwnerTransferSuccess(_receipt)]);
    await _open(tester, fixture.session, gateway);
    await tester.enterText(_field, _targetMembershipId);
    for (final action in [_close, _review]) {
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_hasFocus(tester, _close), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_hasFocus(tester, _review), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(_submit, findsOneWidget);
    for (final action in [_close, _edit, _submit]) {
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  for (final locale in ['zh', 'en']) {
    testWidgets('$locale 软键盘与 200% 字号保留完整输入区', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 283);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await _open(
        tester,
        fixture.session,
        _Gateway([]),
        locale: locale,
        textScaler: const TextScaler.linear(2),
      );
      await tester.enterText(_field, _targetMembershipId);
      await tester.ensureVisible(_field);
      await tester.pumpAndSettle();
      final viewport = find.ancestor(
        of: _field,
        matching: find.byType(SingleChildScrollView),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(viewport).height,
        greaterThanOrEqualTo(tester.getSize(_field).height),
      );
      for (final action in [_close, _review]) {
        final rect = tester.getRect(action);
        expect(rect.bottom, lessThanOrEqualTo(568 - 283));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
    });
  }

  for (final locale in ['zh', 'en']) {
    testWidgets('$locale 320x568 / 200% 全阶段无溢出且状态可达', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      final organizations = ValueNotifier(
        OrganizationDirectoryEntry(
          organizationWorkspaceId: _organizationId,
          organizationName:
              'Long organization 很长的组织名称 ${List.filled(60, '界').join()}',
        ),
      );
      addTearDown(organizations.dispose);
      final pending = Completer<OrganizationOwnerTransferResult>();
      final gateway = _Gateway([
        pending,
        OrganizationOwnerTransferSuccess(_receipt),
      ]);
      await _open(
        tester,
        fixture.session,
        gateway,
        locale: locale,
        textScaler: TextScaler.linear(2),
        organizations: organizations,
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(_field, _targetMembershipId);
      await tester.tap(_review);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      await tester.ensureVisible(_status);
      pending.complete(
        const OrganizationOwnerTransferRejected(
          OrganizationOwnerTransferFailureCode.networkUnavailable,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final target in [_status, _uncertain]) {
        expect(
          tester
              .getSemantics(target)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        await tester.ensureVisible(target);
        expect(tester.getRect(target).isEmpty, isFalse);
      }
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_keepRetry);
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_receipt.organizationOwnerAssignmentId), findsOneWidget);
      await tester.ensureVisible(find.text(_receipt.previousOwnerAssignmentId));
      fixture.identity.emit(const IdentitySnapshot.signedOut());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SelectableText), findsNothing);
      await tester.ensureVisible(_status);
      semantics.dispose();
    });
  }
}

final _dialog = find.byKey(
  const ValueKey('organization-owner-transfer-dialog'),
);
final _field = find.byKey(
  const ValueKey('organization-owner-transfer-target-field'),
);
final _review = find.byKey(
  const ValueKey('organization-owner-transfer-review'),
);
final _submit = find.byKey(
  const ValueKey('organization-owner-transfer-submit'),
);
final _edit = find.byKey(const ValueKey('organization-owner-transfer-edit'));
final _close = find.byKey(const ValueKey('organization-owner-transfer-close'));
final _status = find.byKey(
  const ValueKey('organization-owner-transfer-status'),
);
final _uncertain = find.byKey(
  const ValueKey('organization-owner-transfer-uncertain'),
);
final _keepRetry = find.byKey(
  const ValueKey('organization-owner-transfer-keep-retry'),
);
final _discard = find.byKey(
  const ValueKey('organization-owner-transfer-discard'),
);

bool _hasFocus(WidgetTester tester, Finder finder) {
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

Future<void> _confirmAndSubmit(
  WidgetTester tester,
  AppSession session,
  _Gateway gateway,
) async {
  await _open(tester, session, gateway);
  await tester.enterText(_field, _targetMembershipId);
  await tester.tap(_review);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  AppSession session,
  OrganizationOwnerTransferGateway gateway, {
  String locale = 'zh',
  TextScaler textScaler = TextScaler.noScaling,
  ValueNotifier<OrganizationDirectoryEntry>? organizations,
  String Function()? requestIdGenerator,
}) async {
  Widget dialog(OrganizationDirectoryEntry organization) =>
      OrganizationOwnerTransferDialog(
        text: AppStrings(locale),
        organization: organization,
        gateway: gateway,
        appSession: session,
        requestIdGenerator: requestIdGenerator ?? () => _requestId,
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const ValueKey('open-approval'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => organizations == null
                  ? dialog(_organization)
                  : ValueListenableBuilder<OrganizationDirectoryEntry>(
                      valueListenable: organizations,
                      builder: (_, organization, _) => dialog(organization),
                    ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-approval')));
  await tester.pumpAndSettle();
}

final class _Gateway implements OrganizationOwnerTransferGateway {
  _Gateway(Iterable<Object> results) : _results = Queue.of(results);
  final Queue<Object> _results;
  final calls =
      <
        ({
          String requestId,
          String targetOrganizationMembershipId,
          String organizationWorkspaceId,
        })
      >[];
  var closed = false;

  @override
  Future<OrganizationOwnerTransferResult> transfer({
    required String requestId,
    required String targetOrganizationMembershipId,
    required String organizationWorkspaceId,
  }) async {
    calls.add((
      requestId: requestId,
      targetOrganizationMembershipId: targetOrganizationMembershipId,
      organizationWorkspaceId: organizationWorkspaceId,
    ));
    final next = _results.removeFirst();
    if (next is Completer<OrganizationOwnerTransferResult>) {
      return next.future;
    }
    if (next is OrganizationOwnerTransferResult) return next;
    throw next;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused shareable join operation');
}

final class _Fixture {
  _Fixture(this.identity, this.session, this.context);
  final _IdentitySession identity;
  final AppSession session;
  final _ContextGateway context;

  static Future<_Fixture> create() async {
    final identity = _IdentitySession(_signedIn('subject-a'));
    final context = _ContextGateway();
    final session = AppSession(
      identitySession: identity,
      contextGateway: context,
    );
    await session.start();
    return _Fixture(identity, session, context);
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity operation');
}

final class _ContextGateway implements SessionContextGateway {
  var selectCalls = 0;
  @override
  Future<SessionContextResult> resolve(IdentityAccessToken token) async =>
      SessionContextSuccess(_context(token.value));
  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken token,
    String projectId,
  ) async {
    selectCalls += 1;
    return SessionContextSuccess(_context(token.value, projectB: true));
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused context operation');
}

TrustedSessionContext _context(String subject, {bool projectB = false}) =>
    TrustedSessionContext(
      appUserId: subject == 'subject-a'
          ? '99999999-9999-4999-8999-999999999999'
          : '12222222-2222-4222-8222-222222222222',
      workspace: const WorkspaceContext(
        id: '21111111-1111-4111-8111-111111111111',
        kind: WorkspaceKind.personal,
        name: '个人空间',
      ),
      project: ProjectContext(
        id: projectB
            ? '32222222-2222-4222-8222-222222222222'
            : '31111111-1111-4111-8111-111111111111',
        name: '项目',
      ),
      questionnaireVersion: const QuestionnaireVersionContext(
        id: '41111111-1111-4111-8111-111111111111',
        versionNumber: 1,
      ),
      capabilities: {},
    );

IdentitySnapshot _signedIn(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: '$subject@example.test',
  ),
  expiresAt: DateTime.utc(2030, subject == 'subject-a' ? 1 : 2),
);

const _targetMembershipId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _organizationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _organization = OrganizationDirectoryEntry(
  organizationWorkspaceId: _organizationId,
  organizationName: '测试组织',
);
const _requestId = '12345678-1234-4234-8234-123456789abc';
final _receipt = OrganizationOwnerTransferReceipt(
  ownerTransferContractId: 'organization-owner-transfer:v1',
  organizationWorkspaceId: _organizationId,
  previousOwnerAssignmentId: '55555555-5555-4555-8555-555555555555',
  organizationOwnerAssignmentId: '66666666-6666-4666-8666-666666666666',
  effectiveAtUtc: DateTime.parse('2030-01-02T12:05:06.123Z'),
);
