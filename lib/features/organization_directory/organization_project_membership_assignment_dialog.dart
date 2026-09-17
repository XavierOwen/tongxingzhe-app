import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_project_membership_assignment/organization_project_membership_assignment.dart';

/// Review two known UUID selectors before explicitly assigning a project member.
final class OrganizationProjectMembershipAssignmentDialog
    extends StatefulWidget {
  const OrganizationProjectMembershipAssignmentDialog({
    super.key,
    required this.text,
    required this.organizationWorkspaceId,
    required this.gateway,
    required this.appSession,
    this.requestIdGenerator = secureUuidV4,
    this.fixedTargetOrganizationMembershipId,
  });

  final AppStrings text;
  final String organizationWorkspaceId;
  final OrganizationProjectMembershipAssignmentGateway gateway;
  final AppSession appSession;
  final String Function() requestIdGenerator;
  final String? fixedTargetOrganizationMembershipId;

  @override
  State<OrganizationProjectMembershipAssignmentDialog> createState() =>
      _OrganizationProjectMembershipAssignmentDialogState();
}

enum _AssignmentStage {
  entering,
  confirming,
  submitting,
  succeeded,
  sessionExpired,
}

final class _OrganizationProjectMembershipAssignmentDialogState
    extends State<OrganizationProjectMembershipAssignmentDialog> {
  final _projectController = TextEditingController();
  final _targetController = TextEditingController();
  final _scrollController = ScrollController();
  final _dialogFocus = FocusNode();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  String? _organizationWorkspaceId;
  String? _appUserId;
  String? _projectId;
  String? _targetMembershipId;
  String? _fixedTargetMembershipId;
  String? _requestId;
  OrganizationProjectMembershipAssignmentReceipt? _receipt;
  String? _failureKey;
  var _stage = _AssignmentStage.entering;
  var _submitted = false;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _generation = 0;

  bool get _busy => _stage == _AssignmentStage.submitting;
  String _t(String suffix) =>
      widget.text.t('organizationProjectMembershipAssignment$suffix');

  @override
  void initState() {
    super.initState();
    _organizationWorkspaceId = widget.organizationWorkspaceId.toLowerCase();
    _fixedTargetMembershipId = widget.fixedTargetOrganizationMembershipId
        ?.toLowerCase();
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _AssignmentStage.sessionExpired;
      _organizationWorkspaceId = null;
      _appUserId = null;
      _fixedTargetMembershipId = null;
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
    _projectController.dispose();
    _targetController.dispose();
    _scrollController.dispose();
    _dialogFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_busy && !_uncertain,
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
        key: const ValueKey(
          'organization-project-membership-assignment-dialog',
        ),
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
                    _t(_confirmDiscard ? 'DiscardTitle' : 'Title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 16),
                _content(),
              ],
            ),
          ),
        ),
        actions: _actions(),
      ),
    ),
  );

  Widget _content() {
    if (_confirmDiscard) return Text(_t('DiscardBody'));
    final statusKey = switch (_stage) {
      _AssignmentStage.submitting => 'Submitting',
      _AssignmentStage.succeeded => 'Success',
      _AssignmentStage.sessionExpired => 'Unauthorized',
      _ => _failureKey,
    };
    final organizationId = _organizationWorkspaceId;
    final receipt = _receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey(
              'organization-project-membership-assignment-uncertain',
            ),
            liveRegion: true,
            child: Text(_t('Uncertain')),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey(
              'organization-project-membership-assignment-status',
            ),
            liveRegion: true,
            child: Text(_t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (organizationId != null) ...[
          _value(
            'OrganizationId',
            receipt?.organizationWorkspaceId ?? organizationId,
          ),
          if (receipt != null) ...[
            _value('ContractId', receipt.projectMembershipAssignmentContractId),
            _value('ProjectId', receipt.projectId),
            _value('TargetMembershipId', receipt.organizationMembershipId),
            _value('ProjectMembershipId', receipt.projectMembershipId),
            _value(
              'ActiveFrom',
              receipt.activeFromUtc.toUtc().toIso8601String(),
            ),
            _value(
              'InactiveFrom',
              receipt.inactiveFromUtc?.toUtc().toIso8601String() ??
                  _t('NullEnd'),
            ),
            Text(_t('FreshnessNotice')),
          ] else if (_stage == _AssignmentStage.entering) ...[
            Text(
              _t(
                _fixedTargetMembershipId == null
                    ? 'InputHelp'
                    : 'FixedTargetInputHelp',
              ),
            ),
            const SizedBox(height: 16),
            _field(
              'project',
              _projectController,
              'ProjectIdentifier',
              autofocus: true,
              textInputAction: _fixedTargetMembershipId == null
                  ? TextInputAction.next
                  : TextInputAction.done,
            ),
            const SizedBox(height: 16),
            if (_fixedTargetMembershipId case final target?)
              _value('TargetMembershipId', target)
            else
              _field('target', _targetController, 'TargetMembershipIdentifier'),
          ] else ...[
            _value('ProjectId', _projectId!),
            _value('TargetMembershipId', _targetMembershipId!),
            Text(_t('ConfirmHelp')),
          ],
        ],
      ],
    );
  }

  Widget _field(
    String name,
    TextEditingController controller,
    String label, {
    bool autofocus = false,
    TextInputAction textInputAction = TextInputAction.done,
  }) => TextField(
    key: ValueKey('organization-project-membership-assignment-$name-field'),
    controller: controller,
    autofocus: autofocus,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: textInputAction,
    decoration: InputDecoration(
      labelText: _t(label),
      hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) {
      if (_failureKey != null) setState(() => _failureKey = null);
    },
    onSubmitted: (_) {
      if (textInputAction == TextInputAction.done) _review();
    },
  );

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t(label)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey(
            'organization-project-membership-assignment-keep-retry',
          ),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(_t('KeepRetry')),
        ),
        FilledButton(
          key: const ValueKey(
            'organization-project-membership-assignment-discard',
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('Discard')),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('organization-project-membership-assignment-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(_t('Close')),
      ),
      if (_stage == _AssignmentStage.confirming && !_submitted)
        TextButton(
          key: const ValueKey(
            'organization-project-membership-assignment-edit',
          ),
          onPressed: _edit,
          child: Text(_t('Edit')),
        ),
      if (_stage != _AssignmentStage.succeeded &&
          _stage != _AssignmentStage.sessionExpired)
        FilledButton(
          key: ValueKey(
            _stage == _AssignmentStage.entering
                ? 'organization-project-membership-assignment-review'
                : 'organization-project-membership-assignment-submit',
          ),
          onPressed: _busy
              ? null
              : _stage == _AssignmentStage.entering
              ? _review
              : _assign,
          child: Text(
            _t(
              _stage == _AssignmentStage.entering
                  ? 'Review'
                  : _submitted
                  ? 'Retry'
                  : 'Assign',
            ),
          ),
        ),
    ];
  }

  void _review() {
    if (_stage != _AssignmentStage.entering ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    final projectId = _projectController.text.toLowerCase();
    final targetId =
        _fixedTargetMembershipId ?? _targetController.text.toLowerCase();
    final failure = !_canonicalUuidPattern.hasMatch(_organizationWorkspaceId!)
        ? 'InvalidOrganization'
        : !_canonicalUuidPattern.hasMatch(projectId)
        ? 'InvalidProject'
        : !_canonicalUuidPattern.hasMatch(targetId)
        ? 'InvalidTargetMembership'
        : null;
    if (failure != null) {
      setState(() => _failureKey = failure);
      _scrollToStatus();
      return;
    }
    FocusScope.of(context).unfocus();
    _dialogFocus.requestFocus();
    setState(() {
      _projectId = projectId;
      _targetMembershipId = targetId;
      _failureKey = null;
      _stage = _AssignmentStage.confirming;
    });
    _scrollToStatus();
  }

  void _edit() {
    if (_stage != _AssignmentStage.confirming ||
        _submitted ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    setState(() {
      _projectId = null;
      _targetMembershipId = null;
      _failureKey = null;
      _stage = _AssignmentStage.entering;
    });
    _scrollToStatus();
  }

  Future<void> _assign() async {
    if (_stage != _AssignmentStage.confirming ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    if (_requestId == null) {
      try {
        final generated = widget.requestIdGenerator().toLowerCase();
        if (!_canonicalUuidPattern.hasMatch(generated)) {
          throw const FormatException();
        }
        _requestId = generated;
      } catch (_) {
        setState(() => _failureKey = 'InvalidRequest');
        _scrollToStatus();
        return;
      }
    }
    final generation = ++_generation;
    setState(() {
      _submitted = true;
      _stage = _AssignmentStage.submitting;
      _failureKey = null;
    });
    _scrollToStatus();
    OrganizationProjectMembershipAssignmentResult result;
    try {
      result = await widget.gateway.assign(
        requestId: _requestId!,
        organizationWorkspaceId: _organizationWorkspaceId!,
        projectId: _projectId!,
        targetOrganizationMembershipId: _targetMembershipId!,
      );
    } catch (_) {
      result = const OrganizationProjectMembershipAssignmentRejected(
        OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
      );
    }
    if (!mounted || generation != _generation || !_checkSession()) return;
    switch (result) {
      case OrganizationProjectMembershipAssignmentSuccess(:final receipt):
        setState(() {
          _receipt = receipt;
          _stage = _AssignmentStage.succeeded;
          _failureKey = null;
          _uncertain = false;
        });
      case OrganizationProjectMembershipAssignmentRejected(:final code):
        if (code ==
            OrganizationProjectMembershipAssignmentFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _stage = _AssignmentStage.confirming;
          _failureKey = 'Failure.${code.name}';
          _uncertain = switch (code) {
            OrganizationProjectMembershipAssignmentFailureCode
                .networkUnavailable ||
            OrganizationProjectMembershipAssignmentFailureCode
                .serviceUnavailable ||
            OrganizationProjectMembershipAssignmentFailureCode
                .invalidResponse => true,
            _ => false,
          };
        });
    }
    _scrollToStatus();
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _AssignmentStage.sessionExpired &&
      _appUserId != null &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _appUserId &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _checkSession() {
    if (_isTrustedSnapshot(widget.appSession.current)) return true;
    _invalidateSession();
    return false;
  }

  void _invalidateSession() {
    if (!mounted || _stage == _AssignmentStage.sessionExpired) return;
    _generation += 1;
    setState(() {
      _stage = _AssignmentStage.sessionExpired;
      _projectController.clear();
      _targetController.clear();
      _organizationWorkspaceId = null;
      _appUserId = null;
      _projectId = null;
      _targetMembershipId = null;
      _requestId = null;
      _fixedTargetMembershipId = null;
      _receipt = null;
      _failureKey = null;
      _submitted = false;
      _uncertain = false;
      _confirmDiscard = false;
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
    if (_busy) return;
    if (_confirmDiscard) {
      setState(() => _confirmDiscard = false);
    } else if (_uncertain) {
      setState(() => _confirmDiscard = true);
      _scrollToStatus();
    } else {
      Navigator.of(context).pop();
    }
  }
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
