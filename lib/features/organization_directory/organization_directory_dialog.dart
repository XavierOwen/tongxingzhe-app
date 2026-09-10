import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directed_account_invitation/organization_directed_account_invitation.dart';
import '../../organization_directory/organization_directory.dart';
import '../../organization_membership_self_leave/organization_membership_self_leave.dart';
import 'organization_invitation_create_dialog.dart';
import 'organization_invitation_accept_dialog.dart';
import 'organization_membership_self_leave_dialog.dart';

/// 读取当前账号的组织目录，不改变当前项目。
///
/// Gateway 和 [AppSession] 的生命周期仍由 composition root 管理。
final class OrganizationDirectoryDialog extends StatefulWidget {
  const OrganizationDirectoryDialog({
    super.key,
    required this.text,
    required this.gateway,
    required this.appSession,
    this.selfLeaveGateway =
        const DeferredOrganizationMembershipSelfLeaveGateway(),
    this.invitationGateway =
        const DeferredOrganizationDirectedAccountInvitationGateway(),
  });

  final AppStrings text;
  final OrganizationDirectoryGateway gateway;
  final AppSession appSession;
  final OrganizationMembershipSelfLeaveGateway selfLeaveGateway;
  final OrganizationDirectedAccountInvitationGateway invitationGateway;

  @override
  State<OrganizationDirectoryDialog> createState() =>
      _OrganizationDirectoryDialogState();
}

final class _OrganizationDirectoryDialogState
    extends State<OrganizationDirectoryDialog> {
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  List<OrganizationDirectoryEntry> _organizations = const [];
  OrganizationDirectoryFailureCode? _failure;
  String? _notice;
  String? _trustedAppUserId;
  var _busy = false;
  var _copyingSelfId = false;
  var _sessionInvalidated = false;
  var _requestGeneration = 0;
  var _copyGeneration = 0;

  @override
  void initState() {
    super.initState();
    _trustedAppUserId = _readyAppUserId(widget.appSession.current);
    _sessionInvalidated = _trustedAppUserId == null;
    _sessionSubscription = widget.appSession.changes.listen(_sessionChanged);
    if (!_sessionInvalidated) unawaited(_load());
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    _copyGeneration += 1;
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _close();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AlertDialog(
      key: const ValueKey('organization-directory-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 560),
      scrollable: true,
      title: Text(widget.text.t('organizationDirectoryTitle')),
      content: _content(context),
      actions: [
        TextButton(
          key: const ValueKey('organization-directory-close'),
          onPressed: _close,
          child: Text(widget.text.t('organizationDirectoryClose')),
        ),
        FilledButton(
          key: const ValueKey('organization-directory-refresh'),
          onPressed: _busy || _sessionInvalidated ? null : _load,
          child: Text(widget.text.t('organizationDirectoryRefresh')),
        ),
      ],
    ),
  );

  Widget _content(BuildContext context) {
    final status = _visibleStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('organization-directory-accept-invitation'),
            onPressed: _busy || _sessionInvalidated ? null : _acceptInvitation,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: Text(widget.text.t('organizationInvitationAction')),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.text.t('organizationDirectoryHelp')),
        if (_trustedAppUserId case final appUserId?) ...[
          const SizedBox(height: 16),
          _selfIdentity(context, appUserId),
        ],
        const SizedBox(height: 16),
        if (_notice case final notice?) ...[
          Semantics(
            key: const ValueKey('organization-directory-notice'),
            liveRegion: true,
            child: Text(notice),
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          key: const ValueKey('organization-directory-status'),
          container: true,
          liveRegion: true,
          label: status ?? widget.text.t('organizationDirectoryLoaded'),
          child: ExcludeSemantics(
            child: status == null ? const SizedBox.shrink() : Text(status),
          ),
        ),
        if (_organizations.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var index = 0; index < _organizations.length; index++) ...[
            if (index > 0) const Divider(),
            _entry(context, _organizations[index]),
          ],
        ],
      ],
    );
  }

  Widget _selfIdentity(BuildContext context, String appUserId) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.text.t('organizationDirectoryAppUserIdLabel'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      SelectableText(
        appUserId,
        key: const ValueKey('organization-directory-self-app-user-id'),
      ),
      const SizedBox(height: 4),
      Text(widget.text.t('organizationDirectoryAppUserIdHelp')),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(
          key: const ValueKey('organization-directory-self-app-user-id-copy'),
          onPressed: _copyingSelfId || _sessionInvalidated
              ? null
              : _copySelfAppUserId,
          icon: const Icon(Icons.copy_outlined),
          label: Text(widget.text.t('organizationDirectoryAppUserIdCopy')),
        ),
      ),
    ],
  );

  Widget _entry(BuildContext context, OrganizationDirectoryEntry entry) =>
      Padding(
        key: ValueKey(
          'organization-directory-entry-${entry.organizationWorkspaceId}',
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              entry.organizationName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.text.t('organizationDirectoryIdentifier'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(entry.organizationWorkspaceId),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  key: ValueKey(
                    'organization-invitation-create-'
                    '${entry.organizationWorkspaceId}',
                  ),
                  onPressed: _busy || _sessionInvalidated
                      ? null
                      : () => _createInvitation(entry),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    widget.text.t('organizationInvitationCreateAction'),
                  ),
                ),
                TextButton.icon(
                  key: ValueKey(
                    'organization-leave-${entry.organizationWorkspaceId}',
                  ),
                  onPressed: _busy || _sessionInvalidated
                      ? null
                      : () => _leave(entry),
                  icon: const Icon(Icons.logout),
                  label: Text(widget.text.t('organizationLeaveAction')),
                ),
              ],
            ),
          ],
        ),
      );

  String? get _visibleStatus {
    if (_sessionInvalidated) {
      return widget.text.t('organizationDirectoryUnauthorized');
    }
    if (_busy) return widget.text.t('organizationDirectoryLoading');
    final failure = _failure;
    if (failure != null) return _failureText(failure);
    if (_organizations.isEmpty) {
      return widget.text.t('organizationDirectoryEmpty');
    }
    return null;
  }

  String _failureText(OrganizationDirectoryFailureCode code) => switch (code) {
    OrganizationDirectoryFailureCode.notConfigured => widget.text.t(
      'organizationDirectoryNotConfigured',
    ),
    OrganizationDirectoryFailureCode.unauthorized => widget.text.t(
      'organizationDirectoryUnauthorized',
    ),
    OrganizationDirectoryFailureCode.invalidRequest => widget.text.t(
      'organizationDirectoryInvalidRequest',
    ),
    OrganizationDirectoryFailureCode.forbidden => widget.text.t(
      'organizationDirectoryForbidden',
    ),
    OrganizationDirectoryFailureCode.serviceUnavailable => widget.text.t(
      'organizationDirectoryServiceUnavailable',
    ),
    OrganizationDirectoryFailureCode.networkUnavailable => widget.text.t(
      'organizationDirectoryNetworkUnavailable',
    ),
    OrganizationDirectoryFailureCode.invalidResponse => widget.text.t(
      'organizationDirectoryInvalidResponse',
    ),
  };

  Future<void> _load() async {
    if (_busy || _sessionInvalidated) return;
    if (!_hasTrustedSession(widget.appSession.current)) {
      _invalidateSession();
      return;
    }

    final generation = ++_requestGeneration;
    setState(() {
      _busy = true;
      _organizations = const [];
      _failure = null;
    });

    OrganizationDirectoryResult result;
    try {
      result = await widget.gateway.list();
    } catch (_) {
      result = const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.invalidResponse,
      );
    }

    if (!mounted || generation != _requestGeneration) return;
    if (!_hasTrustedSession(widget.appSession.current)) {
      _invalidateSession();
      return;
    }

    switch (result) {
      case OrganizationDirectorySuccess(:final organizations):
        setState(() {
          _busy = false;
          _organizations = organizations;
        });
      case OrganizationDirectoryRejected(:final code):
        setState(() {
          _busy = false;
          _failure = code;
        });
    }
  }

  Future<void> _copySelfAppUserId() async {
    final appUserId = _trustedAppUserId;
    if (_copyingSelfId ||
        appUserId == null ||
        !_hasTrustedSession(widget.appSession.current)) {
      return;
    }

    final generation = ++_copyGeneration;
    setState(() {
      _copyingSelfId = true;
      _notice = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: appUserId));
      if (!mounted || generation != _copyGeneration) return;
      setState(() {
        _copyingSelfId = false;
        _notice = widget.text.t('organizationDirectoryAppUserIdCopySuccess');
      });
    } catch (_) {
      if (!mounted || generation != _copyGeneration) return;
      setState(() {
        _copyingSelfId = false;
        _notice = widget.text.t('organizationDirectoryAppUserIdCopyFailure');
      });
    }
  }

  void _sessionChanged(AppSessionSnapshot snapshot) {
    if (!_hasTrustedSession(snapshot)) _invalidateSession();
  }

  void _invalidateSession() {
    if (_sessionInvalidated || !mounted) return;
    _requestGeneration += 1;
    _copyGeneration += 1;
    setState(() {
      _sessionInvalidated = true;
      _busy = false;
      _copyingSelfId = false;
      _organizations = const [];
      _notice = null;
      _failure = OrganizationDirectoryFailureCode.unauthorized;
      _trustedAppUserId = null;
    });
  }

  void _close() => Navigator.of(context).pop();

  Future<void> _acceptInvitation() async {
    if (_busy || !_hasTrustedSession(widget.appSession.current)) return;
    final receipt =
        await showDialog<OrganizationDirectedAccountInvitationAcceptReceipt>(
          context: context,
          barrierDismissible: false,
          builder: (_) => OrganizationInvitationAcceptDialog(
            text: widget.text,
            gateway: widget.invitationGateway,
            appSession: widget.appSession,
          ),
        );
    if (!mounted ||
        receipt == null ||
        !_hasTrustedSession(widget.appSession.current)) {
      return;
    }
    setState(() => _notice = widget.text.t('organizationInvitationSuccess'));
    // 接受重放可能描述已结束的成员关系，不按旧 receipt 添加组织行。
    await _load();
  }

  Future<void> _createInvitation(OrganizationDirectoryEntry entry) async {
    if (_busy ||
        !_organizations.contains(entry) ||
        !_hasTrustedSession(widget.appSession.current)) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrganizationInvitationCreateDialog(
        text: widget.text,
        organization: entry,
        gateway: widget.invitationGateway,
        appSession: widget.appSession,
      ),
    );
  }

  Future<void> _leave(OrganizationDirectoryEntry entry) async {
    if (_busy ||
        !_organizations.contains(entry) ||
        !_hasTrustedSession(widget.appSession.current)) {
      return;
    }
    final receipt = await showDialog<OrganizationMembershipSelfLeaveReceipt>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrganizationMembershipSelfLeaveDialog(
        text: widget.text,
        organization: entry,
        gateway: widget.selfLeaveGateway,
        appSession: widget.appSession,
      ),
    );
    if (!mounted ||
        receipt == null ||
        !_hasTrustedSession(widget.appSession.current)) {
      return;
    }
    setState(() => _notice = widget.text.t('organizationLeaveSuccess'));
    // Exact replay may describe an old membership; only a fresh directory
    // tells us whether this organization should still be shown.
    await _load();
  }

  bool _hasTrustedSession(AppSessionSnapshot snapshot) =>
      !_sessionInvalidated &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _trustedAppUserId &&
      _trustedAppUserId != null &&
      widget.appSession.isCurrentUser(_trustedAppUserId!);

  static String? _readyAppUserId(AppSessionSnapshot snapshot) =>
      snapshot.stage == AppSessionStage.ready
      ? snapshot.context?.appUserId
      : null;
}
