import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directed_account_invitation/organization_directed_account_invitation.dart';

/// 绑定收件人先读取在线预览，明确确认后才接受邀请。
/// 结果不确定时只重试原 invitation，历史 receipt 不代表当前成员状态。
final class OrganizationInvitationAcceptDialog extends StatefulWidget {
  const OrganizationInvitationAcceptDialog({
    super.key,
    required this.text,
    required this.gateway,
    required this.appSession,
  });

  final AppStrings text;
  final OrganizationDirectedAccountInvitationGateway gateway;
  final AppSession appSession;

  @override
  State<OrganizationInvitationAcceptDialog> createState() =>
      _OrganizationInvitationAcceptDialogState();
}

enum _InvitationStage { entering, previewing, confirming, accepting, expired }

final class _OrganizationInvitationAcceptDialogState
    extends State<OrganizationInvitationAcceptDialog> {
  final _idController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  OrganizationDirectedAccountInvitationPreview? _preview;
  String? _appUserId;
  String? _invitationId;
  String? _failureKey;
  var _stage = _InvitationStage.entering;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _generation = 0;

  bool get _busy =>
      _stage == _InvitationStage.previewing ||
      _stage == _InvitationStage.accepting;

  @override
  void initState() {
    super.initState();
    _appUserId = widget.appSession.current.context?.appUserId;
    if (!_hasTrustedSession()) _stage = _InvitationStage.expired;
    _sessionSubscription = widget.appSession.changes.listen((_) {
      if (!_hasTrustedSession()) _invalidateSession();
    });
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
    _idController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PopScope<OrganizationDirectedAccountInvitationAcceptReceipt>(
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
            key: const ValueKey('organization-invitation-accept-dialog'),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            constraints: const BoxConstraints(maxWidth: 560),
            title: Text(
              widget.text.t(
                _confirmDiscard
                    ? 'organizationInvitationDiscardTitle'
                    : 'organizationInvitationTitle',
              ),
            ),
            content: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: _content(),
              ),
            ),
            actions: _actions(),
          ),
        ),
      );

  Widget _content() {
    if (_confirmDiscard) {
      return Text(widget.text.t('organizationInvitationDiscardBody'));
    }
    final statusKey = switch (_stage) {
      _InvitationStage.previewing => 'organizationInvitationPreviewing',
      _InvitationStage.accepting => 'organizationInvitationAccepting',
      _InvitationStage.expired => 'organizationInvitationUnauthorized',
      _ => _failureKey,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-invitation-uncertain'),
            liveRegion: true,
            child: Text(widget.text.t('organizationInvitationUncertain')),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-invitation-status'),
            liveRegion: true,
            child: Text(widget.text.t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_stage != _InvitationStage.expired)
          if (_preview case final preview?) ...[
            Text(widget.text.t('organizationInvitationExpiresAt')),
            SelectableText(preview.expiresAtUtc.toUtc().toIso8601String()),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: SelectableText(preview.organizationName),
            ),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationInvitationMembershipNotice')),
            const SizedBox(height: 12),
            Text(widget.text.t('organizationInvitationFreshnessNotice')),
            const SizedBox(height: 12),
            SelectableText(preview.invitationId),
          ] else ...[
            Text(widget.text.t('organizationInvitationInputHelp')),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('organization-invitation-id'),
              controller: _idController,
              enabled: !_busy,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.text.t('organizationInvitationIdentifier'),
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_failureKey != null) setState(() => _failureKey = null);
              },
              onSubmitted: (_) => _loadPreview(),
            ),
          ],
      ],
    );
  }

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-invitation-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationInvitationKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-invitation-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationInvitationDiscard')),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('organization-invitation-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationInvitationClose')),
      ),
      if (_preview != null && !_uncertain)
        TextButton(
          key: const ValueKey('organization-invitation-edit'),
          onPressed: _busy ? null : _editInvitation,
          child: Text(widget.text.t('organizationInvitationEdit')),
        ),
      if (_stage != _InvitationStage.expired)
        FilledButton(
          key: ValueKey(
            _preview == null
                ? 'organization-invitation-preview'
                : 'organization-invitation-accept',
          ),
          onPressed: _busy
              ? null
              : _preview == null
              ? _loadPreview
              : _acceptInvitation,
          child: Text(
            widget.text.t(
              _preview == null
                  ? 'organizationInvitationPreview'
                  : _uncertain
                  ? 'organizationInvitationRetry'
                  : 'organizationInvitationAccept',
            ),
          ),
        ),
    ];
  }

  Future<void> _loadPreview() async {
    if (_busy || !_checkSession()) return;
    final invitationId = _idController.text.trim().toLowerCase();
    if (!_uuidPattern.hasMatch(invitationId)) {
      setState(() => _failureKey = 'organizationInvitationInvalidId');
      _scrollToStatus();
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _invitationId = invitationId;
      _preview = null;
      _failureKey = null;
      _stage = _InvitationStage.previewing;
    });
    _scrollToStatus();
    OrganizationDirectedAccountInvitationPreviewResult result;
    try {
      result = await widget.gateway.preview(invitationId: invitationId);
    } catch (_) {
      result = const OrganizationDirectedAccountInvitationPreviewRejected(
        OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationDirectedAccountInvitationPreviewSuccess(:final preview):
        setState(() {
          _preview = preview;
          _stage = _InvitationStage.confirming;
        });
      case OrganizationDirectedAccountInvitationPreviewRejected(:final code):
        _reject(code, accepting: false);
    }
    _scrollToStatus();
  }

  Future<void> _acceptInvitation() async {
    if (_busy || _preview == null || !_checkSession()) return;
    final generation = ++_generation;
    setState(() {
      _failureKey = null;
      _stage = _InvitationStage.accepting;
    });
    _scrollToStatus();
    OrganizationDirectedAccountInvitationAcceptResult result;
    try {
      result = await widget.gateway.accept(invitationId: _invitationId!);
    } catch (_) {
      result = const OrganizationDirectedAccountInvitationAcceptRejected(
        OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationDirectedAccountInvitationAcceptSuccess(:final receipt):
        if (!mounted) return;
        Navigator.of(context).pop(receipt);
      case OrganizationDirectedAccountInvitationAcceptRejected(:final code):
        _reject(code, accepting: true);
        _scrollToStatus();
    }
  }

  void _reject(
    OrganizationDirectedAccountInvitationFailureCode code, {
    required bool accepting,
  }) {
    if (code == OrganizationDirectedAccountInvitationFailureCode.unauthorized) {
      _invalidateSession();
      return;
    }
    setState(() {
      _stage = accepting
          ? _InvitationStage.confirming
          : _InvitationStage.entering;
      _failureKey = 'organizationInvitationFailure.${code.name}';
      _uncertain |=
          accepting &&
          (code ==
                  OrganizationDirectedAccountInvitationFailureCode
                      .networkUnavailable ||
              code ==
                  OrganizationDirectedAccountInvitationFailureCode
                      .serviceUnavailable ||
              code ==
                  OrganizationDirectedAccountInvitationFailureCode
                      .invalidResponse);
    });
  }

  void _editInvitation() {
    if (_busy || _uncertain || !_checkSession()) return;
    setState(() {
      _preview = null;
      _invitationId = null;
      _failureKey = null;
      _stage = _InvitationStage.entering;
    });
    _scrollToStatus();
  }

  bool _hasTrustedSession() =>
      _stage != _InvitationStage.expired &&
      _appUserId != null &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _checkSession() {
    if (_hasTrustedSession()) return true;
    _invalidateSession();
    return false;
  }

  bool _accepts(int generation) =>
      mounted && generation == _generation && _checkSession();

  void _invalidateSession() {
    if (!mounted || _stage == _InvitationStage.expired) return;
    _generation += 1;
    setState(() {
      _uncertain |= _stage == _InvitationStage.accepting;
      _stage = _InvitationStage.expired;
      _preview = null;
      _invitationId = null;
      _failureKey = null;
      _confirmDiscard = false;
      _idController.clear();
    });
    _scrollToStatus();
  }

  void _scrollToStatus() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
