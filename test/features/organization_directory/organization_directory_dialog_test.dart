import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_directory_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_invitation_accept_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_invitation_create_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_membership_self_leave_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_owner_transfer_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_project_membership_assignment_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_application_approve_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_application_directory_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_application_submit_dialog.dart';
import 'package:tongxingzhe_app/features/organization_directory/organization_shareable_join_link_create_dialog.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/organization_directed_account_invitation/organization_directed_account_invitation.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';
import 'package:tongxingzhe_app/organization_membership_self_leave/organization_membership_self_leave.dart';
import 'package:tongxingzhe_app/organization_owner_transfer/organization_owner_transfer.dart';
import 'package:tongxingzhe_app/organization_project_membership_assignment/organization_project_membership_assignment.dart';
import 'package:tongxingzhe_app/organization_shareable_join/organization_shareable_join.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';

import '../../support/fake_runtime_values.dart';

void main() {
  testWidgets(
    'borrowed session retirement fences late self-leave success without directory refresh',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final directory = _Gateway([
        OrganizationDirectorySuccess(const [_organizationA]),
      ]);
      final pending = Completer<OrganizationMembershipSelfLeaveResult>();
      final gateway = _SelfLeaveGateway([pending]);
      await _open(
        tester,
        fixture.session,
        directory,
        selfLeaveGateway: gateway,
      );
      final leave = find.byKey(
        ValueKey(
          'organization-leave-${_organizationA.organizationWorkspaceId}',
        ),
      );
      await tester.ensureVisible(leave);
      await tester.tap(leave);
      await tester.pumpAndSettle();
      await tester.tap(_leaveConfirm);
      await tester.pumpAndSettle();
      expect(gateway.calls, hasLength(1));
      await tester.runAsync(fixture.session.close);
      await tester.pumpAndSettle();
      expect(_leaveConfirm, findsNothing);
      expect(find.text(_organizationA.organizationWorkspaceId), findsNothing);
      pending.complete(OrganizationMembershipSelfLeaveSuccess(_receipt));
      await tester.pumpAndSettle();
      expect(
        find.byType(OrganizationMembershipSelfLeaveDialog),
        findsOneWidget,
      );
      expect(
        find.text(const AppStrings('zh').t('organizationLeaveUncertain')),
        findsOneWidget,
      );
      await tester.tap(_leaveCancel);
      await tester.pumpAndSettle();
      expect(_leaveDiscard, findsOneWidget);
      await tester.tap(_leaveDiscard);
      await tester.pumpAndSettle();
      expect(directory.listCalls, 1);
      expect(directory.closed, isFalse);
      expect(gateway.closed, isFalse);
    },
  );

  testWidgets('borrowed session retirement hides the self-leave organization', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _SelfLeaveGateway();
    await _openSelfLeave(tester, fixture.session, gateway);
    expect(find.text(_organizationA.organizationWorkspaceId), findsOneWidget);
    await tester.runAsync(fixture.session.close);
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationWorkspaceId), findsNothing);
    expect(_leaveConfirm, findsNothing);
    expect(gateway.calls, isEmpty);
    expect(gateway.closed, isFalse);
  });

  testWidgets('borrowed session retirement fences a late directory result', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([pending]);
    await _open(tester, fixture.session, gateway, settle: false);
    await tester.runAsync(fixture.session.close);
    await tester.pumpAndSettle();
    pending.complete(OrganizationDirectorySuccess(const [_organizationA]));
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationWorkspaceId), findsNothing);
    expect(_selfIdCopy, findsNothing);
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
    expect(gateway.listCalls, 1);
    expect(gateway.closed, isFalse);
  });

  testWidgets('borrowed session retirement clears the organization directory', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final gateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA]),
    ]);
    await _open(tester, fixture.session, gateway);
    expect(find.text(_organizationA.organizationWorkspaceId), findsOneWidget);
    await tester.runAsync(fixture.session.close);
    await tester.pumpAndSettle();
    expect(find.text(_organizationA.organizationWorkspaceId), findsNothing);
    expect(_selfIdCopy, findsNothing);
    expect(tester.widget<FilledButton>(_refresh).onPressed, isNull);
    expect(gateway.closed, isFalse);
  });

  for (final closePath in ['close', 'back', 'escape']) {
    testWidgets('历史邀请回执经 $closePath 返回后父目录只重新读取一次', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final directoryGateway = _Gateway([
        OrganizationDirectorySuccess(const []),
        OrganizationDirectorySuccess(const []),
      ]);
      final receipt = OrganizationDirectedAccountInvitationAcceptReceipt(
        organizationInvitationContractId:
            'organization-directed-account-invitation:v1',
        invitationId: 'abcdefab-cdef-0abc-0def-abcdefabcdef',
        organizationWorkspaceId: _organizationA.organizationWorkspaceId,
        organizationMembershipId: 'abcdefab-cdef-0abc-0def-abcdefabcdec',
        acceptedAtUtc: DateTime.utc(2020, 1, 2, 4, 5, 6),
      );
      final invitationGateway = _InvitationGateway(acceptReceipt: receipt);
      await _open(
        tester,
        fixture.session,
        directoryGateway,
        invitationGateway: invitationGateway,
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-directory-accept-invitation')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organization-invitation-id')),
        receipt.invitationId,
      );
      await tester.tap(
        find.byKey(const ValueKey('organization-invitation-preview')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('organization-invitation-accept')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationInvitationAcceptDialog), findsOneWidget);
      expect(
        find.text(receipt.acceptedAtUtc.toIso8601String()),
        findsOneWidget,
      );
      expect(directoryGateway.listCalls, 1);
      if (closePath == 'close') {
        await tester.tap(
          find.byKey(const ValueKey('organization-invitation-close')),
        );
      } else if (closePath == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.byType(OrganizationInvitationAcceptDialog), findsNothing);
      expect(directoryGateway.listCalls, 2);
      expect(find.text(_organizationA.organizationWorkspaceId), findsNothing);
      expect(
        find.text(const AppStrings('zh').t('organizationInvitationSuccess')),
        findsOneWidget,
      );
      expect(invitationGateway.closed, isFalse);
    });
  }

  for (final pendingDirectory in [false, true]) {
    testWidgets(
      '${pendingDirectory ? '待审批目录' : '手工批准'}沿同一借用gateway进入固定成员项目安排，零自动操作',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.close);
        final directory = _Gateway([
          OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
        ]);
        final join = _ShareableJoinGateway(
          directorySuccess: true,
          approveSuccess: true,
        );
        const approvedMember = 'f1111111-1111-4111-8111-111111111111';
        final assignment = _ProjectMembershipAssignmentGateway(
          OrganizationProjectMembershipAssignmentReceipt(
            projectMembershipAssignmentContractId:
                _projectMembershipAssignmentReceipt
                    .projectMembershipAssignmentContractId,
            organizationWorkspaceId: _organizationB.organizationWorkspaceId,
            projectId: _projectMembershipAssignmentReceipt.projectId,
            organizationMembershipId: approvedMember,
            projectMembershipId:
                _projectMembershipAssignmentReceipt.projectMembershipId,
            activeFromUtc: _projectMembershipAssignmentReceipt.activeFromUtc,
            inactiveFromUtc: null,
          ),
        );
        final initialContext = fixture.session.current.context;
        await _open(
          tester,
          fixture.session,
          directory,
          shareableJoinGateway: join,
          projectMembershipAssignmentGateway: assignment,
        );
        final entry = find.byKey(
          ValueKey(
            'organization-shareable-application-${pendingDirectory ? 'directory' : 'approve'}-${_organizationB.organizationWorkspaceId}',
          ),
        );
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        if (pendingDirectory) {
          expect(
            tester
                .widget<OrganizationShareableJoinApplicationDirectoryDialog>(
                  find.byType(
                    OrganizationShareableJoinApplicationDirectoryDialog,
                  ),
                )
                .projectMembershipAssignmentGateway,
            same(assignment),
          );
          final select = find.byKey(
            const ValueKey(
              'organization-shareable-application-directory-review-$_shareableJoinApplicationId',
            ),
          );
          await tester.ensureVisible(select);
          await tester.tap(select);
          await tester.pumpAndSettle();
        }
        final approval = find.byType(
          OrganizationShareableJoinApplicationApproveDialog,
        );
        expect(
          tester
              .widget<OrganizationShareableJoinApplicationApproveDialog>(
                approval,
              )
              .projectMembershipAssignmentGateway,
          same(assignment),
        );
        final field = find.byKey(
          const ValueKey('organization-shareable-approval-application-field'),
        );
        if (pendingDirectory) {
          expect(
            tester.widget<TextField>(field).controller!.text,
            _shareableJoinApplicationId,
          );
        } else {
          await tester.enterText(field, _shareableJoinApplicationId);
        }
        await tester.tap(
          find.byKey(const ValueKey('organization-shareable-approval-review')),
        );
        await tester.pumpAndSettle();
        expect(join.approveCalls, isEmpty);
        await tester.tap(
          find.byKey(const ValueKey('organization-shareable-approval-submit')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('organization-shareable-approval-assign-project'),
          ),
        );
        await tester.pumpAndSettle();
        final child = find.byType(
          OrganizationProjectMembershipAssignmentDialog,
        );
        final childWidget = tester
            .widget<OrganizationProjectMembershipAssignmentDialog>(child);
        expect(childWidget.gateway, same(assignment));
        expect(childWidget.fixedTargetOrganizationMembershipId, approvedMember);
        expect(
          childWidget.organizationWorkspaceId,
          _organizationB.organizationWorkspaceId,
        );
        expect(assignment.calls, isEmpty);
        expect(
          find.byKey(
            const ValueKey(
              'organization-project-membership-assignment-target-field',
            ),
          ),
          findsNothing,
        );
        await tester.enterText(
          find.byKey(
            const ValueKey(
              'organization-project-membership-assignment-project-field',
            ),
          ),
          _projectMembershipAssignmentReceipt.projectId,
        );
        await tester.tap(
          find.byKey(
            const ValueKey('organization-project-membership-assignment-review'),
          ),
        );
        await tester.pumpAndSettle();
        expect(assignment.calls, isEmpty);
        await tester.tap(
          find.byKey(
            const ValueKey('organization-project-membership-assignment-submit'),
          ),
        );
        await tester.pumpAndSettle();
        expect(assignment.calls, hasLength(1));
        expect(
          assignment.calls.single.organizationWorkspaceId,
          _organizationB.organizationWorkspaceId,
        );
        expect(
          assignment.calls.single.targetOrganizationMembershipId,
          approvedMember,
        );
        expect(
          assignment.calls.single.projectId,
          _projectMembershipAssignmentReceipt.projectId,
        );
        expect(
          assignment.calls.single.requestId,
          isNot(_shareableJoinApplicationId),
        );
        await tester.tap(
          find.byKey(
            const ValueKey('organization-project-membership-assignment-close'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: approval, matching: find.text(approvedMember)),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('organization-shareable-approval-close')),
        );
        await tester.pumpAndSettle();
        expect(directory.listCalls, 1);
        expect(join.directoryCalls.length, pendingDirectory ? 1 : 0);
        expect(join.approveCalls, hasLength(1));
        expect(join.submitCalls, isEmpty);
        expect(join.previewCalls, isEmpty);
        expect(join.closed, isFalse);
        expect(assignment.closeCalls, 0);
        expect(fixture.session.current.context, initialContext);
      },
    );
  }

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
        _contextA.appUserId,
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
    expect(find.text(_contextA.appUserId), findsOneWidget);
    expect(
      find.text(text.t('organizationDirectoryAppUserIdHelp')),
      findsOneWidget,
    );
    expect(
      find.text(text.t('organizationDirectoryInvalidResponse')),
      findsNothing,
    );
  });

  testWidgets('空目录可使用加入链接，预览提交不刷新目录、不切项目或关闭网关', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([OrganizationDirectorySuccess(const [])]);
    final shareableJoinGateway = _ShareableJoinGateway(
      previewReceipt: _shareableJoinPreviewReceipt,
      submitSuccess: true,
    );
    final initialContext = fixture.session.current.context;
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      shareableJoinGateway: shareableJoinGateway,
    );

    final useLink = find.byKey(
      const ValueKey('organization-directory-use-shareable-link'),
    );
    expect(useLink, findsOneWidget);
    await tester.tap(useLink);
    await tester.pumpAndSettle();
    expect(
      find.byType(OrganizationShareableJoinApplicationSubmitDialog),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(
        const ValueKey('organization-shareable-application-link-field'),
      ),
      _shareableJoinLinkId,
    );
    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-application-preview')),
    );
    await tester.pumpAndSettle();
    expect(shareableJoinGateway.previewCalls, [_shareableJoinLinkId]);

    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-application-submit')),
    );
    await tester.pumpAndSettle();
    expect(shareableJoinGateway.submitCalls, hasLength(1));
    expect(
      shareableJoinGateway.submitCalls.single.linkId,
      _shareableJoinLinkId,
    );
    expect(
      shareableJoinGateway.submitCalls.single.applicationId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(shareableJoinGateway.closed, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-application-close')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(OrganizationShareableJoinApplicationSubmitDialog),
      findsNothing,
    );
    expect(find.byType(OrganizationDirectoryDialog), findsOneWidget);
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(shareableJoinGateway.closed, isFalse);
  });

  testWidgets('本人账号编号可复制，复制失败后可重试并通知辅助技术', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe();
    addTearDown(clipboard.close);
    final pending = Completer<OrganizationDirectoryResult>();
    final gateway = _Gateway([pending]);
    const text = AppStrings('zh');
    final semantics = tester.ensureSemantics();

    await _open(tester, fixture.session, gateway, settle: false);
    expect(find.text(text.t('organizationDirectoryLoading')), findsOneWidget);
    expect(
      find.text(text.t('organizationDirectoryAppUserIdLabel')),
      findsOneWidget,
    );
    expect(find.text(_contextA.appUserId), findsOneWidget);

    clipboard.fail = true;
    await tester.tap(_selfIdCopy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_contextA.appUserId]);
    expect(
      find.text(text.t('organizationDirectoryAppUserIdCopyFailure')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(_notice)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    clipboard.fail = false;
    await tester.tap(_selfIdCopy);
    await tester.pumpAndSettle();
    expect(clipboard.values, [_contextA.appUserId, _contextA.appUserId]);
    expect(
      find.text(text.t('organizationDirectoryAppUserIdCopySuccess')),
      findsOneWidget,
    );
    pending.complete(OrganizationDirectorySuccess(const []));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('账号切换立即隐藏本人编号、复制按钮和旧通知', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final clipboard = _ClipboardProbe();
    addTearDown(clipboard.close);
    await _open(
      tester,
      fixture.session,
      _Gateway([OrganizationDirectorySuccess(const [])]),
    );
    await tester.tap(_selfIdCopy);
    await tester.pumpAndSettle();
    expect(
      find.text(
        const AppStrings('zh').t('organizationDirectoryAppUserIdCopySuccess'),
      ),
      findsOneWidget,
    );

    fixture.identity.emit(_signedIn('subject-b'));
    await tester.pumpAndSettle();
    expect(find.text(_contextA.appUserId), findsNothing);
    expect(_selfIdCopy, findsNothing);
    expect(
      find.text(
        const AppStrings('zh').t('organizationDirectoryAppUserIdCopySuccess'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final code in OrganizationDirectoryFailureCode.values) {
    testWidgets('${code.name} 显示对应脱敏提示而不是空目录', (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final gateway = _Gateway([OrganizationDirectoryRejected(code)]);
      const text = AppStrings('zh');
      await _open(tester, fixture.session, gateway);

      expect(find.text(_failureText(text, code)), findsOneWidget);
      expect(find.text(_contextA.appUserId), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('organization-directory-accept-invitation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('organization-directory-use-shareable-link')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'organization-shareable-application-approve-'
          '${organizations.last.organizationWorkspaceId}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'organization-owner-transfer-'
          '${organizations.last.organizationWorkspaceId}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'organization-project-member-assign-'
          '${organizations.last.organizationWorkspaceId}',
        ),
      ),
      findsOneWidget,
    );
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
    final selfIdCopyRect = tester.getSemantics(_selfIdCopy).rect;
    expect(selfIdCopyRect.width, greaterThanOrEqualTo(48));
    expect(selfIdCopyRect.height, greaterThanOrEqualTo(48));
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

  testWidgets('每个组织行创建加入链接固定选中组织，不刷新目录且不猜 owner', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final shareableJoinGateway = _ShareableJoinGateway();
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      shareableJoinGateway: shareableJoinGateway,
    );

    final create = find.byKey(
      ValueKey(
        'organization-shareable-link-create-'
        '${_organizationB.organizationWorkspaceId}',
      ),
    );
    expect(create, findsOneWidget);
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    final dialog = find.byType(OrganizationShareableJoinLinkCreateDialog);
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
    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-link-create-submit')),
    );
    await tester.pumpAndSettle();
    expect(
      shareableJoinGateway.calls.single.organizationWorkspaceId,
      _organizationB.organizationWorkspaceId,
    );
    expect(directoryGateway.listCalls, 1);
    expect(shareableJoinGateway.closed, isFalse);
  });

  testWidgets('待审批入口固定所选组织；只预填批准表单且不自动读写或切项目', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directory = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final gateway = _ShareableJoinGateway(directorySuccess: true);
    final initialContext = fixture.session.current.context;
    await _open(
      tester,
      fixture.session,
      directory,
      shareableJoinGateway: gateway,
    );
    final entry = find.byKey(
      ValueKey(
        'organization-shareable-application-directory-${_organizationB.organizationWorkspaceId}',
      ),
    );
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(gateway.directoryCalls, [_organizationB.organizationWorkspaceId]);
    final dialog = find.byType(
      OrganizationShareableJoinApplicationDirectoryDialog,
    );
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
    final review = find.byKey(
      const ValueKey(
        'organization-shareable-application-directory-review-$_shareableJoinApplicationId',
      ),
    );
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    final field = find.byKey(
      const ValueKey('organization-shareable-approval-application-field'),
    );
    expect(
      tester.widget<TextField>(field).controller!.text,
      _shareableJoinApplicationId,
    );
    expect(gateway.approveCalls, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-approval-close')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('organization-shareable-application-directory-close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(directory.listCalls, 1);
    expect(gateway.directoryCalls, [_organizationB.organizationWorkspaceId]);
    expect(gateway.previewCalls, isEmpty);
    expect(gateway.submitCalls, isEmpty);
    expect(gateway.approveCalls, isEmpty);
    expect(gateway.closed, isFalse);
    expect(fixture.session.current.context, initialContext);
  });

  testWidgets('每个组织行批准加入申请固定选中组织，成功留窗且不刷新目录', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final shareableJoinGateway = _ShareableJoinGateway(approveSuccess: true);
    final initialContext = fixture.session.current.context;
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      shareableJoinGateway: shareableJoinGateway,
    );

    final approve = find.byKey(
      ValueKey(
        'organization-shareable-application-approve-'
        '${_organizationB.organizationWorkspaceId}',
      ),
    );
    expect(approve, findsOneWidget);
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();

    final dialog = find.byType(
      OrganizationShareableJoinApplicationApproveDialog,
    );
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
      find.byKey(
        const ValueKey('organization-shareable-approval-application-field'),
      ),
      _shareableJoinApplicationId,
    );
    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-approval-review')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('organization-shareable-approval-submit')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-approval-submit')),
    );
    await tester.pumpAndSettle();
    expect(shareableJoinGateway.approveCalls, hasLength(1));
    expect(
      shareableJoinGateway.approveCalls.single.organizationWorkspaceId,
      _organizationB.organizationWorkspaceId,
    );
    expect(
      shareableJoinGateway.approveCalls.single.applicationId,
      _shareableJoinApplicationId,
    );
    expect(
      find.byKey(const ValueKey('organization-shareable-approval-status')),
      findsOneWidget,
    );
    expect(
      find.text(
        const AppStrings('zh').t('organizationShareableApprovalSuccess'),
      ),
      findsOneWidget,
    );
    expect(shareableJoinGateway.previewCalls, isEmpty);
    expect(shareableJoinGateway.submitCalls, isEmpty);
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(shareableJoinGateway.closed, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('organization-shareable-approval-close')),
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.byType(OrganizationDirectoryDialog), findsOneWidget);
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(shareableJoinGateway.closed, isFalse);
  });

  testWidgets('每个组织行交接所有权固定选中组织，核对后提交并显示回执', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final ownerTransferGateway = _OwnerTransferGateway(
      _organizationOwnerTransferReceipt,
    );
    final initialContext = fixture.session.current.context;
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      ownerTransferGateway: ownerTransferGateway,
    );

    final transfer = find.byKey(
      ValueKey(
        'organization-owner-transfer-${_organizationB.organizationWorkspaceId}',
      ),
    );
    await tester.ensureVisible(transfer);
    await tester.tap(transfer);
    await tester.pumpAndSettle();

    final dialog = find.byType(OrganizationOwnerTransferDialog);
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

    await tester.enterText(
      find.byKey(const ValueKey('organization-owner-transfer-target-field')),
      '  ${_targetOrganizationMembershipId.toUpperCase()}  ',
    );
    await tester.tap(
      find.byKey(const ValueKey('organization-owner-transfer-review')),
    );
    await tester.pumpAndSettle();
    expect(ownerTransferGateway.calls, isEmpty);
    expect(find.text(_targetOrganizationMembershipId), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('organization-owner-transfer-submit')),
    );
    await tester.pumpAndSettle();
    expect(ownerTransferGateway.calls, hasLength(1));
    final call = ownerTransferGateway.calls.single;
    expect(
      call.organizationWorkspaceId,
      _organizationB.organizationWorkspaceId,
    );
    expect(
      call.targetOrganizationMembershipId,
      _targetOrganizationMembershipId,
    );
    expect(
      call.requestId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    for (final value in [
      _organizationOwnerTransferReceipt.organizationWorkspaceId,
      _organizationOwnerTransferReceipt.ownerTransferContractId,
      _organizationOwnerTransferReceipt.previousOwnerAssignmentId,
      _organizationOwnerTransferReceipt.organizationOwnerAssignmentId,
      _organizationOwnerTransferReceipt.effectiveAtUtc
          .toUtc()
          .toIso8601String(),
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(value)),
        findsOneWidget,
      );
    }
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(ownerTransferGateway.closed, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('organization-owner-transfer-close')),
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.byType(OrganizationDirectoryDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OrganizationDirectoryDialog),
        matching: find.text(_organizationB.organizationWorkspaceId),
      ),
      findsOneWidget,
    );
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(ownerTransferGateway.closed, isFalse);
  });

  testWidgets('每个组织行分配项目成员固定选中组织，核对后提交并显示历史回执', (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final directoryGateway = _Gateway([
      OrganizationDirectorySuccess(const [_organizationA, _organizationB]),
    ]);
    final assignmentGateway = _ProjectMembershipAssignmentGateway(
      _projectMembershipAssignmentReceipt,
    );
    final initialContext = fixture.session.current.context;
    await _open(
      tester,
      fixture.session,
      directoryGateway,
      projectMembershipAssignmentGateway: assignmentGateway,
    );

    final assign = find.byKey(
      ValueKey(
        'organization-project-member-assign-'
        '${_organizationB.organizationWorkspaceId}',
      ),
    );
    await tester.ensureVisible(assign);
    await tester.tap(assign);
    await tester.pumpAndSettle();

    final dialog = find.byType(OrganizationProjectMembershipAssignmentDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(_organizationB.organizationWorkspaceId),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(
        const ValueKey(
          'organization-project-membership-assignment-project-field',
        ),
      ),
      _assignmentProjectId.toUpperCase(),
    );
    await tester.enterText(
      find.byKey(
        const ValueKey(
          'organization-project-membership-assignment-target-field',
        ),
      ),
      _assignmentTargetMembershipId.toUpperCase(),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('organization-project-membership-assignment-review'),
      ),
    );
    await tester.pumpAndSettle();
    expect(assignmentGateway.calls, isEmpty);
    expect(find.text(_assignmentProjectId), findsOneWidget);
    expect(find.text(_assignmentTargetMembershipId), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('organization-project-membership-assignment-submit'),
      ),
    );
    await tester.pumpAndSettle();
    expect(assignmentGateway.calls, hasLength(1));
    final call = assignmentGateway.calls.single;
    expect(
      call.organizationWorkspaceId,
      _organizationB.organizationWorkspaceId,
    );
    expect(call.projectId, _assignmentProjectId);
    expect(call.targetOrganizationMembershipId, _assignmentTargetMembershipId);
    expect(
      call.requestId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    for (final value in [
      _projectMembershipAssignmentReceipt.projectMembershipAssignmentContractId,
      _projectMembershipAssignmentReceipt.organizationWorkspaceId,
      _projectMembershipAssignmentReceipt.projectId,
      _projectMembershipAssignmentReceipt.organizationMembershipId,
      _projectMembershipAssignmentReceipt.projectMembershipId,
      _projectMembershipAssignmentReceipt.activeFromUtc
          .toUtc()
          .toIso8601String(),
      const AppStrings(
        'zh',
      ).t('organizationProjectMembershipAssignmentNullEnd'),
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(value)),
        findsOneWidget,
      );
    }
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(assignmentGateway.closeCalls, 0);

    await tester.tap(
      find.byKey(
        const ValueKey('organization-project-membership-assignment-close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.byType(OrganizationDirectoryDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OrganizationDirectoryDialog),
        matching: find.text(_organizationB.organizationWorkspaceId),
      ),
      findsOneWidget,
    );
    expect(directoryGateway.listCalls, 1);
    expect(fixture.session.current.context, initialContext);
    expect(assignmentGateway.closeCalls, 0);
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
    final leave = find.byKey(
      ValueKey('organization-leave-${_organizationA.organizationWorkspaceId}'),
    );
    await tester.ensureVisible(leave);
    await tester.tap(leave);
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
    final leave = find.byKey(
      ValueKey('organization-leave-${_organizationA.organizationWorkspaceId}'),
    );
    await tester.ensureVisible(leave);
    await tester.tap(leave);
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
final _selfIdCopy = find.byKey(
  const ValueKey('organization-directory-self-app-user-id-copy'),
);
final _notice = find.byKey(const ValueKey('organization-directory-notice'));
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
  OrganizationShareableJoinGateway shareableJoinGateway =
      const DeferredOrganizationShareableJoinGateway(),
  OrganizationOwnerTransferGateway ownerTransferGateway =
      const DeferredOrganizationOwnerTransferGateway(),
  OrganizationProjectMembershipAssignmentGateway
      projectMembershipAssignmentGateway =
      const DeferredOrganizationProjectMembershipAssignmentGateway(),
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
    shareableJoinGateway: shareableJoinGateway,
    ownerTransferGateway: ownerTransferGateway,
    projectMembershipAssignmentGateway: projectMembershipAssignmentGateway,
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
  OrganizationShareableJoinGateway shareableJoinGateway =
      const DeferredOrganizationShareableJoinGateway(),
  OrganizationOwnerTransferGateway ownerTransferGateway =
      const DeferredOrganizationOwnerTransferGateway(),
  OrganizationProjectMembershipAssignmentGateway
      projectMembershipAssignmentGateway =
      const DeferredOrganizationProjectMembershipAssignmentGateway(),
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
                shareableJoinGateway: shareableJoinGateway,
                ownerTransferGateway: ownerTransferGateway,
                projectMembershipAssignmentGateway:
                    projectMembershipAssignmentGateway,
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

final class _ClipboardProbe {
  _ClipboardProbe() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            values.add(
              (call.arguments! as Map<Object?, Object?>)['text']! as String,
            );
            if (fail) throw StateError('clipboard failed');
          }
          return null;
        });
  }

  final values = <String>[];
  var fail = false;

  void close() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
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
  _InvitationGateway({this.acceptReceipt});

  final OrganizationDirectedAccountInvitationAcceptReceipt? acceptReceipt;
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
  }) async {
    if (acceptReceipt == null) {
      throw UnsupportedError('unused directory wiring preview');
    }
    return OrganizationDirectedAccountInvitationPreviewSuccess(
      OrganizationDirectedAccountInvitationPreview(
        organizationInvitationPreviewContractId:
            'organization-directed-account-invitation-preview:v1',
        invitationId: invitationId,
        organizationName: '组织',
        expiresAtUtc: DateTime.utc(2030, 1, 8),
      ),
    );
  }

  @override
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  }) async {
    if (acceptReceipt case final receipt?) {
      return OrganizationDirectedAccountInvitationAcceptSuccess(receipt);
    }
    throw UnsupportedError('unused directory wiring accept');
  }

  @override
  Future<void> close() async => closed = true;
}

typedef _ShareableJoinCall = ({String linkId, String organizationWorkspaceId});
typedef _ShareableJoinSubmitCall = ({String applicationId, String linkId});
typedef _ShareableJoinApproveCall = ({
  String organizationWorkspaceId,
  String applicationId,
});

final class _ShareableJoinGateway implements OrganizationShareableJoinGateway {
  _ShareableJoinGateway({
    this.previewReceipt,
    this.submitSuccess = false,
    this.approveSuccess = false,
    this.directorySuccess = false,
  });

  final OrganizationShareableJoinLinkPreviewReceipt? previewReceipt;
  final bool submitSuccess;
  final bool approveSuccess;
  final bool directorySuccess;
  final directoryCalls = <String>[];
  final calls = <_ShareableJoinCall>[];
  final previewCalls = <String>[];
  final submitCalls = <_ShareableJoinSubmitCall>[];
  final approveCalls = <_ShareableJoinApproveCall>[];
  var closed = false;

  @override
  Future<OrganizationShareableJoinApplicationDirectoryResult>
  listPendingApplications({required String organizationWorkspaceId}) async {
    directoryCalls.add(organizationWorkspaceId);
    return directorySuccess
        ? OrganizationShareableJoinApplicationDirectorySuccess(
            OrganizationShareableJoinApplicationDirectoryReceipt(
              organizationShareableJoinApplicationDirectoryContractId:
                  'organization-shareable-join-application-directory:v1',
              organizationWorkspaceId: organizationWorkspaceId,
              observedAtUtc: DateTime.utc(2026, 9, 18),
              applications: [
                OrganizationShareableJoinApplicationDirectoryRecord(
                  applicationId: _shareableJoinApplicationId,
                  linkId: _shareableJoinLinkId,
                  submittedAtUtc: DateTime.utc(2026, 9, 17),
                  expiresAtUtc: DateTime.utc(2026, 9, 24),
                ),
              ],
            ),
          )
        : const OrganizationShareableJoinApplicationDirectoryRejected(
            OrganizationShareableJoinFailureCode.notConfigured,
          );
  }

  @override
  Future<OrganizationShareableJoinLinkCreateResult> createLink({
    required String linkId,
    required String organizationWorkspaceId,
  }) async {
    calls.add((
      linkId: linkId,
      organizationWorkspaceId: organizationWorkspaceId,
    ));
    return const OrganizationShareableJoinLinkCreateRejected(
      OrganizationShareableJoinFailureCode.notConfigured,
    );
  }

  @override
  Future<OrganizationShareableJoinLinkPreviewResult> previewLink({
    required String linkId,
  }) async {
    previewCalls.add(linkId);
    final receipt = previewReceipt;
    return receipt == null
        ? const OrganizationShareableJoinLinkPreviewRejected(
            OrganizationShareableJoinFailureCode.notConfigured,
          )
        : OrganizationShareableJoinLinkPreviewSuccess(receipt);
  }

  @override
  Future<OrganizationShareableJoinApplicationSubmitResult> submitApplication({
    required String applicationId,
    required String linkId,
  }) async {
    submitCalls.add((applicationId: applicationId, linkId: linkId));
    return submitSuccess
        ? OrganizationShareableJoinApplicationSubmitSuccess(
            OrganizationShareableJoinApplicationSubmitReceipt(
              organizationShareableJoinApplicationContractId:
                  'organization-shareable-join-application:v1',
              applicationId: applicationId,
              linkId: linkId,
              organizationWorkspaceId: _organizationA.organizationWorkspaceId,
              submittedAtUtc: DateTime.utc(2026, 9, 15, 18),
              expiresAtUtc: DateTime.utc(2026, 9, 16, 18),
            ),
          )
        : const OrganizationShareableJoinApplicationSubmitRejected(
            OrganizationShareableJoinFailureCode.notConfigured,
          );
  }

  @override
  Future<OrganizationShareableJoinApplicationApproveResult> approveApplication({
    required String organizationWorkspaceId,
    required String applicationId,
  }) async {
    approveCalls.add((
      organizationWorkspaceId: organizationWorkspaceId,
      applicationId: applicationId,
    ));
    return approveSuccess
        ? OrganizationShareableJoinApplicationApproveSuccess(
            OrganizationShareableJoinApplicationApproveReceipt(
              organizationShareableJoinApplicationContractId:
                  'organization-shareable-join-application:v1',
              applicationId: applicationId,
              organizationWorkspaceId: organizationWorkspaceId,
              organizationMembershipId: 'f1111111-1111-4111-8111-111111111111',
              approvedAtUtc: DateTime.utc(2026, 9, 16, 18),
            ),
          )
        : const OrganizationShareableJoinApplicationApproveRejected(
            OrganizationShareableJoinFailureCode.notConfigured,
          );
  }

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
  var closed = false;

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
  Future<void> close() async => closed = true;
}

typedef _OwnerTransferCall = ({
  String requestId,
  String organizationWorkspaceId,
  String targetOrganizationMembershipId,
});

final class _OwnerTransferGateway implements OrganizationOwnerTransferGateway {
  _OwnerTransferGateway(this.receipt);

  final OrganizationOwnerTransferReceipt receipt;
  final calls = <_OwnerTransferCall>[];
  var closed = false;

  @override
  Future<OrganizationOwnerTransferResult> transfer({
    required String requestId,
    required String organizationWorkspaceId,
    required String targetOrganizationMembershipId,
  }) async {
    calls.add((
      requestId: requestId,
      organizationWorkspaceId: organizationWorkspaceId,
      targetOrganizationMembershipId: targetOrganizationMembershipId,
    ));
    return OrganizationOwnerTransferSuccess(receipt);
  }

  @override
  Future<void> close() async => closed = true;
}

typedef _ProjectMembershipAssignmentCall = ({
  String requestId,
  String organizationWorkspaceId,
  String projectId,
  String targetOrganizationMembershipId,
});

final class _ProjectMembershipAssignmentGateway
    implements OrganizationProjectMembershipAssignmentGateway {
  _ProjectMembershipAssignmentGateway(this.receipt);

  final OrganizationProjectMembershipAssignmentReceipt receipt;
  final calls = <_ProjectMembershipAssignmentCall>[];
  var closeCalls = 0;

  @override
  Future<OrganizationProjectMembershipAssignmentResult> assign({
    required String requestId,
    required String organizationWorkspaceId,
    required String projectId,
    required String targetOrganizationMembershipId,
  }) async {
    calls.add((
      requestId: requestId,
      organizationWorkspaceId: organizationWorkspaceId,
      projectId: projectId,
      targetOrganizationMembershipId: targetOrganizationMembershipId,
    ));
    return OrganizationProjectMembershipAssignmentSuccess(receipt);
  }

  @override
  Future<void> close() async => closeCalls += 1;
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
const _shareableJoinLinkId = 'e1111111-1111-4111-8111-111111111111';
const _shareableJoinApplicationId = 'e2222222-2222-4222-8222-222222222222';
const _targetOrganizationMembershipId = 'f3333333-3333-4333-8333-333333333333';
const _assignmentProjectId = '51111111-1111-4111-8111-111111111111';
const _assignmentTargetMembershipId = '52222222-2222-4222-8222-222222222222';

final _shareableJoinPreviewReceipt =
    OrganizationShareableJoinLinkPreviewReceipt(
      organizationShareableJoinLinkPreviewContractId:
          'organization-shareable-join-link-preview:v1',
      linkId: _shareableJoinLinkId,
      organizationName: _organizationA.organizationName,
      expiresAtUtc: DateTime.utc(2026, 9, 16, 18),
    );

final _receipt = OrganizationMembershipSelfLeaveReceipt(
  membershipSelfLeaveContractId: 'organization-membership-self-leave:v1',
  organizationWorkspaceId: _organizationA.organizationWorkspaceId,
  organizationMembershipId: 'd1111111-1111-4111-8111-111111111111',
  effectiveAtUtc: DateTime.utc(2026, 9, 7, 12),
);

final _organizationOwnerTransferReceipt = OrganizationOwnerTransferReceipt(
  ownerTransferContractId: 'organization-owner-transfer:v1',
  organizationWorkspaceId: _organizationB.organizationWorkspaceId,
  previousOwnerAssignmentId: 'g1111111-1111-4111-8111-111111111111',
  organizationOwnerAssignmentId: 'g2222222-2222-4222-8222-222222222222',
  effectiveAtUtc: DateTime.utc(2026, 9, 16, 18),
);

final _projectMembershipAssignmentReceipt =
    OrganizationProjectMembershipAssignmentReceipt(
      projectMembershipAssignmentContractId:
          'organization-project-membership-assignment:v1',
      organizationWorkspaceId: _organizationB.organizationWorkspaceId,
      projectId: _assignmentProjectId,
      organizationMembershipId: _assignmentTargetMembershipId,
      projectMembershipId: '53333333-3333-4333-8333-333333333333',
      activeFromUtc: DateTime.utc(2026, 9, 16, 19),
      inactiveFromUtc: null,
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
