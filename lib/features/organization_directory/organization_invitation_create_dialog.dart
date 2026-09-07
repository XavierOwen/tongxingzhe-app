import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directed_account_invitation/organization_directed_account_invitation.dart';
import '../../organization_directory/organization_directory.dart';

/// 为选定组织创建一份绑定已有账号的定向邀请。
///
/// 不确定结果只在本对话框内保留同一 organization、target 和
/// invitation UUID。Gateway 和 [AppSession] 的生命周期仍由 composition root 管理。
final class OrganizationInvitationCreateDialog extends StatefulWidget {
  const OrganizationInvitationCreateDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
    this.invitationIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationDirectedAccountInvitationGateway gateway;
  final AppSession appSession;
  final String Function() invitationIdGenerator;

  @override
  State<OrganizationInvitationCreateDialog> createState() =>
      _OrganizationInvitationCreateDialogState();
}

enum _CreateInvitationStage { entering, submitting, succeeded, sessionExpired }

final class _OrganizationInvitationCreateDialogState
    extends State<OrganizationInvitationCreateDialog> {
  final _targetController = TextEditingController();
  final _targetFocusNode = FocusNode();
  final _scrollController = ScrollController();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;

  String? _appUserId;
  String? _intentTargetAppUserId;
  String? _invitationId;
  OrganizationDirectedAccountInvitationCreateReceipt? _receipt;
  String? _failureKey;
  String? _copyStatusKey;
  var _stage = _CreateInvitationStage.entering;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _copying = false;
  var _generation = 0;

  bool get _busy => _stage == _CreateInvitationStage.submitting || _copying;

  @override
  void initState() {
    super.initState();
    _appUserId = widget.appSession.current.context?.appUserId;
    if (!_hasTrustedSession()) {
      _stage = _CreateInvitationStage.sessionExpired;
    }
    _sessionSubscription = widget.appSession.changes.listen((_) {
      if (!_hasTrustedSession()) _invalidateSession();
    });
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
    _targetController.dispose();
    _targetFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
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
        key: const ValueKey('organization-invitation-create-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(
          widget.text.t(
            _confirmDiscard
                ? 'organizationInvitationCreateDiscardTitle'
                : 'organizationInvitationCreateTitle',
          ),
        ),
        content: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: _content(context),
          ),
        ),
        actions: _actions(),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    if (_confirmDiscard) {
      return Text(widget.text.t('organizationInvitationCreateDiscardBody'));
    }

    final statusKey = switch (_stage) {
      _CreateInvitationStage.submitting =>
        'organizationInvitationCreateSubmitting',
      _CreateInvitationStage.succeeded => 'organizationInvitationCreateSuccess',
      _CreateInvitationStage.sessionExpired =>
        'organizationInvitationCreateUnauthorized',
      _CreateInvitationStage.entering => _failureKey,
    };
    final receipt = _receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-invitation-create-uncertain'),
            liveRegion: true,
            child: Text(widget.text.t('organizationInvitationCreateUncertain')),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-invitation-create-status'),
            liveRegion: true,
            child: Text(widget.text.t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_copyStatusKey case final copyStatusKey?) ...[
          Semantics(
            key: const ValueKey('organization-invitation-create-copy-status'),
            liveRegion: true,
            child: Text(widget.text.t(copyStatusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_stage != _CreateInvitationStage.sessionExpired) ...[
          Semantics(
            header: true,
            child: SelectableText(
              widget.organization.organizationName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.text.t('organizationInvitationCreateOrganizationId')),
          const SizedBox(height: 4),
          SelectableText(widget.organization.organizationWorkspaceId),
          const SizedBox(height: 16),
          if (receipt == null) ...[
            Text(widget.text.t('organizationInvitationCreateOwnerHelp')),
            const SizedBox(height: 12),
            Text(widget.text.t('organizationInvitationCreateDeliveryHelp')),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('organization-invitation-create-target-id'),
              controller: _targetController,
              focusNode: _targetFocusNode,
              autofocus: true,
              readOnly: _busy || _uncertain,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.text.t(
                  'organizationInvitationCreateTargetId',
                ),
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_uncertain || _failureKey == null) return;
                setState(() => _failureKey = null);
              },
              onSubmitted: (_) => unawaited(_submit()),
            ),
          ] else ...[
            Text(widget.text.t('organizationInvitationCreateInvitationId')),
            const SizedBox(height: 4),
            SelectableText(receipt.invitationId),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationInvitationCreateIssuedAt')),
            const SizedBox(height: 4),
            SelectableText(receipt.issuedAtUtc.toUtc().toIso8601String()),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationInvitationCreateExpiresAt')),
            const SizedBox(height: 4),
            SelectableText(receipt.expiresAtUtc.toUtc().toIso8601String()),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationInvitationCreateNoDelivery')),
            const SizedBox(height: 12),
            Text(widget.text.t('organizationInvitationCreateFreshnessNotice')),
          ],
        ],
      ],
    );
  }

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-invitation-create-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationInvitationCreateKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-invitation-create-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationInvitationCreateDiscard')),
        ),
      ];
    }

    return [
      TextButton(
        key: const ValueKey('organization-invitation-create-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationInvitationCreateClose')),
      ),
      if (_stage == _CreateInvitationStage.succeeded)
        FilledButton.icon(
          key: const ValueKey('organization-invitation-create-copy'),
          onPressed: _busy ? null : _copyInvitationId,
          icon: const Icon(Icons.copy_outlined),
          label: Text(widget.text.t('organizationInvitationCreateCopy')),
        )
      else if (_stage != _CreateInvitationStage.sessionExpired)
        FilledButton(
          key: const ValueKey('organization-invitation-create-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(
            widget.text.t(
              _uncertain
                  ? 'organizationInvitationCreateRetry'
                  : 'organizationInvitationCreateSubmit',
            ),
          ),
        ),
    ];
  }

  Future<void> _submit() async {
    if (_stage != _CreateInvitationStage.entering ||
        _busy ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }

    late final String targetAppUserId;
    late final String invitationId;
    if (_uncertain) {
      targetAppUserId = _intentTargetAppUserId!;
      invitationId = _invitationId!;
    } else {
      targetAppUserId = _targetController.text.trim().toLowerCase();
      if (!_uuidPattern.hasMatch(targetAppUserId)) {
        setState(() {
          _failureKey = 'organizationInvitationCreateInvalidTarget';
          _copyStatusKey = null;
        });
        _targetFocusNode.requestFocus();
        _scrollToStatus();
        return;
      }

      if (_intentTargetAppUserId != targetAppUserId) {
        try {
          final generated = widget.invitationIdGenerator().toLowerCase();
          if (!_uuidPattern.hasMatch(generated)) throw const FormatException();
          _intentTargetAppUserId = targetAppUserId;
          _invitationId = generated;
        } catch (_) {
          setState(() {
            _failureKey = 'organizationInvitationCreateInvalidRequest';
            _copyStatusKey = null;
          });
          _scrollToStatus();
          return;
        }
      }
      invitationId = _invitationId!;
    }

    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _stage = _CreateInvitationStage.submitting;
      _failureKey = null;
      _copyStatusKey = null;
    });
    _scrollToStatus();

    OrganizationDirectedAccountInvitationCreateResult result;
    try {
      result = await widget.gateway.create(
        invitationId: invitationId,
        organizationWorkspaceId: widget.organization.organizationWorkspaceId,
        targetAppUserId: targetAppUserId,
      );
    } catch (_) {
      result = const OrganizationDirectedAccountInvitationCreateRejected(
        OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;

    switch (result) {
      case OrganizationDirectedAccountInvitationCreateSuccess(:final receipt):
        setState(() {
          _receipt = receipt;
          _stage = _CreateInvitationStage.succeeded;
          _failureKey = null;
          _uncertain = false;
        });
      case OrganizationDirectedAccountInvitationCreateRejected(:final code):
        if (code ==
            OrganizationDirectedAccountInvitationFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        final uncertain = _uncertain || _isUncertain(code);
        setState(() {
          _stage = _CreateInvitationStage.entering;
          _failureKey = 'organizationInvitationCreateFailure.${code.name}';
          _uncertain = uncertain;
        });
        if (!uncertain) _targetFocusNode.requestFocus();
    }
    _scrollToStatus();
  }

  Future<void> _copyInvitationId() async {
    final receipt = _receipt;
    if (_busy || receipt == null || !_checkSession()) return;
    final generation = ++_generation;
    setState(() {
      _copying = true;
      _copyStatusKey = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: receipt.invitationId));
      if (!_accepts(generation)) return;
      setState(() {
        _copying = false;
        _copyStatusKey = 'organizationInvitationCreateCopySuccess';
      });
    } catch (_) {
      if (!_accepts(generation)) return;
      setState(() {
        _copying = false;
        _copyStatusKey = 'organizationInvitationCreateCopyFailure';
      });
    }
    _scrollToStatus();
  }

  bool _hasTrustedSession() =>
      _stage != _CreateInvitationStage.sessionExpired &&
      _appUserId != null &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _checkSession() {
    if (_hasTrustedSession()) return true;
    _invalidateSession();
    return false;
  }

  bool _accepts(int generation) {
    if (!mounted || generation != _generation) return false;
    return _checkSession();
  }

  void _invalidateSession() {
    if (!mounted || _stage == _CreateInvitationStage.sessionExpired) return;
    _generation += 1;
    _targetController.clear();
    setState(() {
      _stage = _CreateInvitationStage.sessionExpired;
      _intentTargetAppUserId = null;
      _invitationId = null;
      _receipt = null;
      _failureKey = null;
      _copyStatusKey = null;
      _uncertain = false;
      _confirmDiscard = false;
      _copying = false;
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

  static bool _isUncertain(
    OrganizationDirectedAccountInvitationFailureCode code,
  ) => switch (code) {
    OrganizationDirectedAccountInvitationFailureCode.conflict ||
    OrganizationDirectedAccountInvitationFailureCode.serviceUnavailable ||
    OrganizationDirectedAccountInvitationFailureCode.networkUnavailable ||
    OrganizationDirectedAccountInvitationFailureCode.invalidResponse => true,
    _ => false,
  };
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
