import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directory/organization_directory.dart';
import '../../organization_project_membership_assignment/organization_project_membership_assignment.dart';
import '../../organization_shareable_join/organization_shareable_join.dart';
import 'organization_project_membership_assignment_dialog.dart';

/// 核对已知申请 UUID 后，批准选定组织的入组申请。
final class OrganizationShareableJoinApplicationApproveDialog
    extends StatefulWidget {
  const OrganizationShareableJoinApplicationApproveDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
    this.initialApplicationId,
    this.projectMembershipAssignmentGateway =
        const DeferredOrganizationProjectMembershipAssignmentGateway(),
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationShareableJoinGateway gateway;
  final AppSession appSession;
  final String? initialApplicationId;
  final OrganizationProjectMembershipAssignmentGateway
  projectMembershipAssignmentGateway;

  @override
  State<OrganizationShareableJoinApplicationApproveDialog> createState() =>
      _OrganizationShareableJoinApplicationApproveDialogState();
}

enum _ApprovalStage {
  entering,
  confirming,
  submitting,
  succeeded,
  sessionExpired,
}

final class _OrganizationShareableJoinApplicationApproveDialogState
    extends State<OrganizationShareableJoinApplicationApproveDialog> {
  final _applicationController = TextEditingController();
  final _scrollController = ScrollController();
  final _dialogFocus = FocusNode();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  OrganizationDirectoryEntry? _organization;
  String? _appUserId;
  String? _applicationId;
  OrganizationShareableJoinApplicationApproveReceipt? _receipt;
  String? _failureKey;
  var _stage = _ApprovalStage.entering;
  var _submitted = false;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _generation = 0;
  var _openingAssignment = false;

  bool get _busy => _stage == _ApprovalStage.submitting;

  @override
  void initState() {
    super.initState();
    _organization = widget.organization;
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _ApprovalStage.sessionExpired;
      _organization = null;
      _appUserId = null;
    } else {
      _applicationController.text = widget.initialApplicationId ?? '';
    }
    _sessionSubscription = widget.appSession.changes.listen(
      (snapshot) {
        if (!_isTrustedSnapshot(snapshot)) _invalidateSession();
      },
      onError: (Object _, StackTrace _) => _invalidateSession(),
      onDone: _invalidateSession,
    );
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
    _applicationController.dispose();
    _scrollController.dispose();
    _dialogFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_busy && !_uncertain && !_openingAssignment,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _requestClose();
    },
    child: Focus(
      focusNode: _dialogFocus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _requestClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        key: const ValueKey('organization-shareable-approval-dialog'),
        insetPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 24,
        ),
        contentPadding: MediaQuery.viewInsetsOf(context).bottom > 0
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : null,
        constraints: const BoxConstraints(maxWidth: 560),
        content: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    widget.text.t(
                      _confirmDiscard
                          ? 'organizationShareableApprovalDiscardTitle'
                          : 'organizationShareableApprovalTitle',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 16),
                _content(context),
              ],
            ),
          ),
        ),
        actions: _actions(),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    if (_confirmDiscard) {
      return Text(widget.text.t('organizationShareableApprovalDiscardBody'));
    }
    final statusKey = switch (_stage) {
      _ApprovalStage.submitting => 'organizationShareableApprovalSubmitting',
      _ApprovalStage.succeeded => 'organizationShareableApprovalSuccess',
      _ApprovalStage.sessionExpired =>
        'organizationShareableApprovalUnauthorized',
      _ => _failureKey,
    };
    final organization = _organization;
    final receipt = _receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-shareable-approval-uncertain'),
            liveRegion: true,
            child: Text(
              widget.text.t('organizationShareableApprovalUncertain'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-shareable-approval-status'),
            liveRegion: true,
            child: Text(widget.text.t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (organization != null) ...[
          Semantics(
            header: true,
            child: SelectableText(
              organization.organizationName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 16),
          _value(
            'organizationShareableApprovalOrganizationId',
            receipt?.organizationWorkspaceId ??
                organization.organizationWorkspaceId,
          ),
          if (receipt != null) ...[
            _value(
              'organizationShareableApprovalApplicationId',
              receipt.applicationId,
            ),
            _value(
              'organizationShareableApprovalMembershipId',
              receipt.organizationMembershipId,
            ),
            _value(
              'organizationShareableApprovalApprovedAt',
              receipt.approvedAtUtc.toUtc().toIso8601String(),
            ),
            Text(widget.text.t('organizationShareableApprovalFreshnessNotice')),
          ] else if (_stage == _ApprovalStage.entering) ...[
            Text(widget.text.t('organizationShareableApprovalInputHelp')),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey(
                'organization-shareable-approval-application-field',
              ),
              controller: _applicationController,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.text.t(
                  'organizationShareableApprovalApplicationIdentifier',
                ),
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_failureKey != null) setState(() => _failureKey = null);
              },
              onSubmitted: (_) => _review(),
            ),
          ] else ...[
            _value(
              'organizationShareableApprovalApplicationId',
              _applicationId!,
            ),
            Text(widget.text.t('organizationShareableApprovalConfirmHelp')),
          ],
        ],
      ],
    );
  }

  Widget _value(String labelKey, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.text.t(labelKey)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-shareable-approval-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationShareableApprovalKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-shareable-approval-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationShareableApprovalDiscard')),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('organization-shareable-approval-close'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: _busy || _openingAssignment ? null : _requestClose,
        child: Text(widget.text.t('organizationShareableApprovalClose')),
      ),
      if (_stage == _ApprovalStage.succeeded)
        FilledButton(
          key: const ValueKey('organization-shareable-approval-assign-project'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _openingAssignment ? null : _assignProject,
          child: Text(
            widget.text.t('organizationShareableApprovalAssignProject'),
          ),
        ),
      if (_stage == _ApprovalStage.confirming && !_submitted)
        TextButton(
          key: const ValueKey('organization-shareable-approval-edit'),
          onPressed: _edit,
          child: Text(widget.text.t('organizationShareableApprovalEdit')),
        ),
      if (_stage != _ApprovalStage.succeeded &&
          _stage != _ApprovalStage.sessionExpired)
        FilledButton(
          key: ValueKey(
            _stage == _ApprovalStage.entering
                ? 'organization-shareable-approval-review'
                : 'organization-shareable-approval-submit',
          ),
          onPressed: _busy
              ? null
              : _stage == _ApprovalStage.entering
              ? _review
              : _approve,
          child: Text(
            widget.text.t(
              _stage == _ApprovalStage.entering
                  ? 'organizationShareableApprovalReview'
                  : _submitted
                  ? 'organizationShareableApprovalRetry'
                  : 'organizationShareableApprovalApprove',
            ),
          ),
        ),
    ];
  }

  void _review() {
    if (_stage != _ApprovalStage.entering ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    final applicationId = _applicationController.text.trim().toLowerCase();
    if (!_canonicalUuidPattern.hasMatch(applicationId)) {
      setState(
        () => _failureKey = 'organizationShareableApprovalInvalidApplication',
      );
      _scrollToStatus();
      return;
    }
    FocusScope.of(context).unfocus();
    _dialogFocus.requestFocus();
    setState(() {
      _applicationId = applicationId;
      _failureKey = null;
      _stage = _ApprovalStage.confirming;
    });
    _scrollToStatus();
  }

  void _edit() {
    if (_stage != _ApprovalStage.confirming ||
        _submitted ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    setState(() {
      _applicationId = null;
      _failureKey = null;
      _stage = _ApprovalStage.entering;
    });
    _scrollToStatus();
  }

  Future<void> _approve() async {
    if (_stage != _ApprovalStage.confirming ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    final applicationId = _applicationId!;
    final organizationWorkspaceId = _organization!.organizationWorkspaceId;
    final generation = ++_generation;
    setState(() {
      _submitted = true;
      _stage = _ApprovalStage.submitting;
      _failureKey = null;
    });
    _scrollToStatus();
    OrganizationShareableJoinApplicationApproveResult result;
    try {
      result = await widget.gateway.approveApplication(
        organizationWorkspaceId: organizationWorkspaceId,
        applicationId: applicationId,
      );
    } catch (_) {
      result = const OrganizationShareableJoinApplicationApproveRejected(
        OrganizationShareableJoinFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationShareableJoinApplicationApproveSuccess(:final receipt):
        setState(() {
          _receipt = receipt;
          _stage = _ApprovalStage.succeeded;
          _failureKey = null;
          _uncertain = false;
        });
      case OrganizationShareableJoinApplicationApproveRejected(:final code):
        if (code == OrganizationShareableJoinFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _stage = _ApprovalStage.confirming;
          _failureKey = 'organizationShareableApprovalFailure.${code.name}';
          _uncertain = _isUncertain(code);
        });
    }
    _scrollToStatus();
  }

  Future<void> _assignProject() async {
    if (_stage != _ApprovalStage.succeeded ||
        _openingAssignment ||
        !_checkSession()) {
      return;
    }
    final receipt = _receipt!;
    final generation = _generation;
    setState(() => _openingAssignment = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrganizationProjectMembershipAssignmentDialog(
        text: widget.text,
        organizationWorkspaceId: receipt.organizationWorkspaceId,
        fixedTargetOrganizationMembershipId: receipt.organizationMembershipId,
        gateway: widget.projectMembershipAssignmentGateway,
        appSession: widget.appSession,
      ),
    );
    if (!_accepts(generation)) return;
    setState(() => _openingAssignment = false);
    _dialogFocus.requestFocus();
    _scrollToStatus();
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _ApprovalStage.sessionExpired &&
      _appUserId != null &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _appUserId &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _checkSession() {
    if (_isTrustedSnapshot(widget.appSession.current)) return true;
    _invalidateSession();
    return false;
  }

  bool _accepts(int generation) {
    if (!mounted || generation != _generation) return false;
    return _checkSession();
  }

  void _invalidateSession() {
    if (!mounted || _stage == _ApprovalStage.sessionExpired) return;
    _generation += 1;
    setState(() {
      _stage = _ApprovalStage.sessionExpired;
      _applicationController.clear();
      _organization = null;
      _appUserId = null;
      _applicationId = null;
      _receipt = null;
      _failureKey = null;
      _submitted = false;
      _uncertain = false;
      _confirmDiscard = false;
      _openingAssignment = false;
    });
    _scrollToStatus();
  }

  void _scrollToStatus() {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  void _requestClose() {
    if (_busy || _openingAssignment) return;
    if (_confirmDiscard) {
      setState(() => _confirmDiscard = false);
    } else if (_uncertain) {
      setState(() => _confirmDiscard = true);
      _scrollToStatus();
    } else {
      Navigator.of(context).pop();
    }
  }

  static bool _isUncertain(OrganizationShareableJoinFailureCode code) =>
      switch (code) {
        OrganizationShareableJoinFailureCode.networkUnavailable ||
        OrganizationShareableJoinFailureCode.serviceUnavailable ||
        OrganizationShareableJoinFailureCode.invalidResponse => true,
        _ => false,
      };
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
