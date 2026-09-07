import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directory/organization_directory.dart';
import '../../organization_membership_self_leave/organization_membership_self_leave.dart';
import '../../privacy/offline_pii_vault.dart';

/// 先清除选定组织的本地敏感缓存，再提交一次明确的成员退出请求。
/// 不确定结果仅在这个对话框内保留相同 UUID，receipt 不代表当前成员状态。
final class OrganizationMembershipSelfLeaveDialog extends StatefulWidget {
  const OrganizationMembershipSelfLeaveDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
    this.requestIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationMembershipSelfLeaveGateway gateway;
  final AppSession appSession;
  final String Function() requestIdGenerator;

  @override
  State<OrganizationMembershipSelfLeaveDialog> createState() =>
      _OrganizationMembershipSelfLeaveDialogState();
}

enum _LeaveStage { ready, clearing, submitting, sessionExpired }

final class _OrganizationMembershipSelfLeaveDialogState
    extends State<OrganizationMembershipSelfLeaveDialog> {
  final _contentScrollController = ScrollController();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  String? _appUserId;
  String? _requestId;
  String? _failureKey;
  var _stage = _LeaveStage.ready;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _generation = 0;

  bool get _busy =>
      _stage == _LeaveStage.clearing || _stage == _LeaveStage.submitting;

  @override
  void initState() {
    super.initState();
    _appUserId = widget.appSession.current.context?.appUserId;
    if (!_hasTrustedSession()) _stage = _LeaveStage.sessionExpired;
    _sessionSubscription = widget.appSession.changes.listen((_) {
      if (!_hasTrustedSession()) _invalidateSession();
    });
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PopScope<OrganizationMembershipSelfLeaveReceipt>(
        canPop: !_busy && !_uncertain,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestClose();
        },
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _requestClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AlertDialog(
            key: const ValueKey('organization-membership-self-leave-dialog'),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            constraints: const BoxConstraints(maxWidth: 560),
            title: Text(
              widget.text.t(
                _confirmDiscard
                    ? 'organizationLeaveDiscardTitle'
                    : 'organizationLeaveTitle',
              ),
            ),
            content: Scrollbar(
              controller: _contentScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _contentScrollController,
                child: _content(),
              ),
            ),
            actions: _actions(),
          ),
        ),
      );

  Widget _content() {
    if (_confirmDiscard) {
      return Text(widget.text.t('organizationLeaveDiscardBody'));
    }
    final statusKey = switch (_stage) {
      _LeaveStage.clearing => 'organizationLeaveClearing',
      _LeaveStage.submitting => 'organizationLeaveSubmitting',
      _LeaveStage.sessionExpired => 'organizationLeaveUnauthorized',
      _LeaveStage.ready => _failureKey,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-leave-uncertain'),
            liveRegion: true,
            child: Text(widget.text.t('organizationLeaveUncertain')),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-leave-status'),
            liveRegion: true,
            child: Text(widget.text.t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_stage != _LeaveStage.sessionExpired) ...[
          Semantics(
            header: true,
            child: SelectableText(widget.organization.organizationName),
          ),
          const SizedBox(height: 16),
          Text(widget.text.t('organizationLeaveCacheNotice')),
          const SizedBox(height: 12),
          Text(widget.text.t('organizationLeaveHelp')),
          const SizedBox(height: 12),
          SelectableText(widget.organization.organizationWorkspaceId),
        ],
      ],
    );
  }

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-leave-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationLeaveKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-leave-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationLeaveDiscard')),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('organization-leave-cancel'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationLeaveCancel')),
      ),
      if (_stage != _LeaveStage.sessionExpired)
        FilledButton(
          key: const ValueKey('organization-leave-confirm'),
          onPressed: _busy ? null : _submit,
          child: Text(
            widget.text.t(
              _requestId == null
                  ? 'organizationLeaveConfirm'
                  : 'organizationLeaveRetry',
            ),
          ),
        ),
    ];
  }

  Future<void> _submit() async {
    if (_busy || !_hasTrustedSession()) {
      if (!_hasTrustedSession()) _invalidateSession();
      return;
    }
    try {
      _requestId ??= widget.requestIdGenerator();
    } catch (_) {
      setState(() => _failureKey = 'organizationLeaveInvalidRequest');
      _scrollToStatus();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _stage = _LeaveStage.clearing;
      _failureKey = null;
    });
    _scrollToStatus();

    OfflinePiiWorkspaceDeletionResult cleanup;
    try {
      cleanup = await widget.appSession.clearOrganizationOfflinePii(
        expectedAppUserId: _appUserId!,
        organizationWorkspaceId: widget.organization.organizationWorkspaceId,
      );
    } catch (_) {
      cleanup = OfflinePiiWorkspaceDeletionResult.unavailable;
    }
    if (!_accepts(generation)) return;
    if (cleanup != OfflinePiiWorkspaceDeletionResult.deleted &&
        cleanup != OfflinePiiWorkspaceDeletionResult.notPresent) {
      setState(() {
        _stage = _LeaveStage.ready;
        _failureKey = 'organizationLeaveCleanupFailed';
      });
      _scrollToStatus();
      return;
    }

    setState(() => _stage = _LeaveStage.submitting);
    _scrollToStatus();
    OrganizationMembershipSelfLeaveResult result;
    try {
      result = await widget.gateway.leave(
        requestId: _requestId!,
        organizationWorkspaceId: widget.organization.organizationWorkspaceId,
      );
    } catch (_) {
      result = const OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationMembershipSelfLeaveSuccess(:final receipt):
        if (!mounted) return;
        Navigator.of(context).pop(receipt);
      case OrganizationMembershipSelfLeaveRejected(:final code):
        setState(() {
          _stage = _LeaveStage.ready;
          _failureKey = 'organizationLeaveFailure.${code.name}';
          _uncertain |= switch (code) {
            OrganizationMembershipSelfLeaveFailureCode.serviceUnavailable ||
            OrganizationMembershipSelfLeaveFailureCode.networkUnavailable ||
            OrganizationMembershipSelfLeaveFailureCode.invalidResponse => true,
            _ => false,
          };
        });
        _scrollToStatus();
    }
  }

  bool _hasTrustedSession() =>
      _stage != _LeaveStage.sessionExpired &&
      _appUserId != null &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _accepts(int generation) {
    if (!mounted || generation != _generation) return false;
    if (!_hasTrustedSession()) {
      _invalidateSession();
      return false;
    }
    return true;
  }

  void _invalidateSession() {
    if (!mounted || _stage == _LeaveStage.sessionExpired) return;
    _generation += 1;
    setState(() {
      _uncertain |= _stage == _LeaveStage.submitting;
      _stage = _LeaveStage.sessionExpired;
      _failureKey = null;
      _confirmDiscard = false;
    });
    _scrollToStatus();
  }

  void _scrollToStatus() {
    if (_contentScrollController.hasClients) {
      _contentScrollController.jumpTo(0);
    }
  }

  void _requestClose() {
    if (_busy) return;
    if (_uncertain) {
      setState(() => _confirmDiscard = true);
      _scrollToStatus();
    } else {
      Navigator.of(context).pop();
    }
  }
}
