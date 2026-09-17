import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directory/organization_directory.dart';
import '../../organization_shareable_join/organization_shareable_join.dart';
import 'organization_shareable_join_application_approve_dialog.dart';

/// 固定组织的一次待审批观察；批准仍由独立窗口明确提交。
final class OrganizationShareableJoinApplicationDirectoryDialog
    extends StatefulWidget {
  const OrganizationShareableJoinApplicationDirectoryDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationShareableJoinGateway gateway;
  final AppSession appSession;

  @override
  State<OrganizationShareableJoinApplicationDirectoryDialog> createState() =>
      _OrganizationShareableJoinApplicationDirectoryDialogState();
}

final class _OrganizationShareableJoinApplicationDirectoryDialogState
    extends State<OrganizationShareableJoinApplicationDirectoryDialog> {
  final _focus = FocusNode();
  StreamSubscription<AppSessionSnapshot>? _subscription;
  OrganizationDirectoryEntry? _organization;
  OrganizationShareableJoinApplicationDirectoryReceipt? _receipt;
  OrganizationShareableJoinFailureCode? _failure;
  String? _appUserId;
  var _busy = false;
  var _openingApproval = false;
  var _expired = false;
  var _approvalClosed = false;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _organization = widget.organization;
    _appUserId = widget.appSession.current.context?.appUserId;
    if (!_trusted(widget.appSession.current)) {
      _expired = true;
      _organization = null;
      _appUserId = null;
    }
    _subscription = widget.appSession.changes.listen(
      (snapshot) {
        if (!_trusted(snapshot)) _invalidate();
      },
      onError: (Object _, StackTrace _) => _invalidate(),
      onDone: _invalidate,
    );
    if (!_expired) unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_subscription?.cancel());
    _focus.dispose();
    super.dispose();
  }

  bool _trusted(AppSessionSnapshot snapshot) =>
      !_expired &&
      _appUserId != null &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _appUserId &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _accepts(int generation) {
    if (!mounted || generation != _generation) return false;
    if (_trusted(widget.appSession.current)) return true;
    _invalidate();
    return false;
  }

  void _invalidate() {
    if (!mounted || _expired) return;
    _generation++;
    setState(() {
      _expired = true;
      _organization = null;
      _appUserId = null;
      _receipt = null;
      _failure = null;
      _busy = false;
      _openingApproval = false;
      _approvalClosed = false;
    });
  }

  Future<void> _load() async {
    if (_busy || _openingApproval || _expired) return;
    if (!_trusted(widget.appSession.current)) {
      _invalidate();
      return;
    }
    final workspace = _organization!.organizationWorkspaceId;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _receipt = null;
      _failure = null;
      _approvalClosed = false;
    });
    OrganizationShareableJoinApplicationDirectoryResult result;
    try {
      result = await widget.gateway.listPendingApplications(
        organizationWorkspaceId: workspace,
      );
    } catch (_) {
      result = const OrganizationShareableJoinApplicationDirectoryRejected(
        OrganizationShareableJoinFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationShareableJoinApplicationDirectorySuccess(:final receipt):
        setState(() {
          _busy = false;
          _receipt = receipt;
        });
      case OrganizationShareableJoinApplicationDirectoryRejected(:final code):
        if (code == OrganizationShareableJoinFailureCode.unauthorized) {
          _invalidate();
          return;
        }
        setState(() {
          _busy = false;
          _failure = code;
        });
    }
  }

  Future<void> _review(
    OrganizationShareableJoinApplicationDirectoryRecord record,
  ) async {
    if (_busy ||
        _openingApproval ||
        _expired ||
        !(_receipt?.applications.contains(record) ?? false)) {
      return;
    }
    if (!_trusted(widget.appSession.current)) {
      _invalidate();
      return;
    }
    final generation = _generation;
    final organization = _organization!;
    setState(() => _openingApproval = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrganizationShareableJoinApplicationApproveDialog(
        text: widget.text,
        organization: organization,
        gateway: widget.gateway,
        appSession: widget.appSession,
        initialApplicationId: record.applicationId,
      ),
    );
    if (!_accepts(generation)) return;
    setState(() {
      _openingApproval = false;
      _approvalClosed = true;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          !_openingApproval) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AlertDialog(
      key: const ValueKey(
        'organization-shareable-application-directory-dialog',
      ),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Semantics(
        header: true,
        namesRoute: true,
        child: Text(
          widget.text.t('organizationShareableApplicationDirectoryTitle'),
        ),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_organization case final organization?) ...[
              Text(
                organization.organizationName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _value(
                'organizationShareableApprovalOrganizationId',
                organization.organizationWorkspaceId,
              ),
            ],
            Text(
              widget.text.t('organizationShareableApplicationDirectoryHelp'),
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                widget.text.t(
                  _expired
                      ? 'organizationShareableApplicationDirectorySessionExpired'
                      : _busy
                      ? 'organizationShareableApplicationDirectoryLoading'
                      : _failure != null
                      ? 'organizationShareableApplicationDirectoryFailure.${_failure!.name}'
                      : _receipt?.applications.isEmpty == true
                      ? 'organizationShareableApplicationDirectoryEmpty'
                      : _approvalClosed
                      ? 'organizationShareableApplicationDirectoryApprovalClosed'
                      : 'organizationShareableApplicationDirectoryLoaded',
                ),
                key: const ValueKey(
                  'organization-shareable-application-directory-status',
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_receipt case final receipt?) ...[
              const SizedBox(height: 16),
              _value(
                'organizationShareableApplicationDirectoryObservedAt',
                receipt.observedAtUtc.toIso8601String(),
              ),
              for (final record in receipt.applications) ...[
                const Divider(height: 32),
                _value(
                  'organizationShareableApprovalApplicationId',
                  record.applicationId,
                ),
                ExpansionTile(
                  key: ValueKey(
                    'organization-shareable-application-directory-details-${record.applicationId}',
                  ),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    widget.text.t(
                      'organizationShareableApplicationDirectoryDetails',
                    ),
                  ),
                  children: [
                    _value(
                      'organizationShareableApplicationDirectoryLinkId',
                      record.linkId,
                    ),
                    _value(
                      'organizationShareableApplicationDirectorySubmittedAt',
                      record.submittedAtUtc.toIso8601String(),
                    ),
                    _value(
                      'organizationShareableApplicationDirectoryExpiresAt',
                      record.expiresAtUtc.toIso8601String(),
                    ),
                    Text(
                      widget.text.t(
                        'organizationShareableApplicationDirectoryLinkNotice',
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: ValueKey(
                      'organization-shareable-application-directory-review-${record.applicationId}',
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _openingApproval ? null : () => _review(record),
                    child: Text(
                      widget.text.t(
                        'organizationShareableApplicationDirectoryReview',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey(
            'organization-shareable-application-directory-close',
          ),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _openingApproval
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationShareableApprovalClose')),
        ),
        FilledButton(
          key: const ValueKey(
            'organization-shareable-application-directory-refresh',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy || _openingApproval || _expired ? null : _load,
          child: Text(widget.text.t('organizationDirectoryRefresh')),
        ),
      ],
    ),
  );

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.text.t(label)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
}
