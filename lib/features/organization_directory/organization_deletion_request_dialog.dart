import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_deletion_recovery/organization_deletion_recovery.dart';
import '../../organization_directory/organization_directory.dart';
import '../../privacy/offline_pii_vault.dart';

/// Confirms one organization deletion request and returns its receipt.
final class OrganizationDeletionRequestDialog extends StatefulWidget {
  const OrganizationDeletionRequestDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
    this.requestIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationDeletionRecoveryGateway gateway;
  final AppSession appSession;
  final String Function() requestIdGenerator;

  @override
  State<OrganizationDeletionRequestDialog> createState() =>
      _OrganizationDeletionRequestDialogState();
}

enum _RequestStage { ready, clearing, submitting, succeeded, sessionExpired }

final class _OrganizationDeletionRequestDialogState
    extends State<OrganizationDeletionRequestDialog> {
  final _scrollController = ScrollController();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  OrganizationDirectoryEntry? _organization;
  OrganizationDeletionRequestReceipt? _receipt;
  String? _appUserId;
  String? _requestId;
  String? _failureKey;
  var _stage = _RequestStage.ready;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _generation = 0;

  bool get _busy =>
      _stage == _RequestStage.clearing || _stage == _RequestStage.submitting;

  @override
  void initState() {
    super.initState();
    _organization = widget.organization;
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _RequestStage.sessionExpired;
      _organization = null;
      _appUserId = null;
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
    _generation++;
    unawaited(_sessionSubscription?.cancel());
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PopScope<OrganizationDeletionRequestReceipt>(
        canPop:
            !_busy &&
            !_uncertain &&
            !_confirmDiscard &&
            _stage != _RequestStage.succeeded,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestClose();
        },
        child: Focus(
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
            key: const ValueKey('organization-deletion-request-dialog'),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            constraints: const BoxConstraints(maxWidth: 560),
            title: Semantics(
              header: true,
              namesRoute: true,
              child: Text(
                widget.text.t(
                  _confirmDiscard
                      ? 'organizationDeletionRequestDiscardTitle'
                      : _stage == _RequestStage.succeeded
                      ? 'organizationDeletionRequestReceiptTitle'
                      : 'organizationDeletionRequestTitle',
                ),
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
      return Text(widget.text.t('organizationDeletionRequestDiscardBody'));
    }
    if (_stage == _RequestStage.sessionExpired) {
      return _liveStatus('organizationDeletionRequestUnauthorized');
    }
    final receipt = _receipt;
    if (receipt != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _liveStatus('organizationDeletionRequestSuccess'),
          const SizedBox(height: 16),
          _value(
            'organizationDeletionRequestOrganizationId',
            receipt.organizationWorkspaceId,
          ),
          _value(
            'organizationDeletionRequestDeletionRequestId',
            receipt.deletionRequestId,
          ),
          _value(
            'organizationDeletionRequestEffectiveAt',
            receipt.effectiveAtUtc,
          ),
          _value(
            'organizationDeletionRequestPurgeAfter',
            receipt.purgeAfterUtc,
          ),
          Text(widget.text.t('organizationDeletionRequestReceiptNotice')),
        ],
      );
    }

    final organization = _organization;
    if (organization == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          _liveStatus('organizationDeletionRequestUncertain'),
          const SizedBox(height: 12),
        ],
        if (_failureKey case final key?) ...[
          _liveStatus(key),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(
            organization.organizationName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        _value(
          'organizationDeletionRequestOrganizationId',
          organization.organizationWorkspaceId,
        ),
        Text(widget.text.t('organizationDeletionRequestHelp')),
        const SizedBox(height: 12),
        Text(widget.text.t('organizationDeletionRequestCacheNotice')),
        if (_stage == _RequestStage.clearing) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _liveStatus('organizationDeletionRequestClearing'),
        ],
        if (_stage == _RequestStage.submitting) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _liveStatus('organizationDeletionRequestSubmitting'),
        ],
      ],
    );
  }

  Widget _value(String key, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.text.t(key)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );

  Widget _liveStatus(String key) => Semantics(
    key: ValueKey('organization-deletion-request-status-$key'),
    liveRegion: true,
    child: Text(widget.text.t(key)),
  );

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-deletion-request-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationDeletionRequestKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-deletion-request-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationDeletionRequestDiscard')),
        ),
      ];
    }
    if (_stage == _RequestStage.succeeded) {
      return [
        FilledButton(
          key: const ValueKey('organization-deletion-request-done'),
          onPressed: _close,
          child: Text(widget.text.t('organizationDeletionRequestClose')),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('organization-deletion-request-cancel'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationDeletionRequestCancel')),
      ),
      if (_stage != _RequestStage.sessionExpired)
        FilledButton(
          key: const ValueKey('organization-deletion-request-confirm'),
          onPressed: _busy ? null : _submit,
          child: Text(
            widget.text.t(
              _requestId == null
                  ? 'organizationDeletionRequestConfirm'
                  : 'organizationDeletionRequestRetry',
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
    final organization = _organization;
    if (organization == null) return;
    if (_requestId == null) {
      try {
        final requestId = widget.requestIdGenerator().toLowerCase();
        if (!_uuidPattern.hasMatch(requestId)) throw const FormatException();
        _requestId = requestId;
      } catch (_) {
        setState(() {
          _failureKey = 'organizationDeletionRequestInvalidRequest';
        });
        return;
      }
    }

    final generation = ++_generation;
    setState(() {
      _stage = _RequestStage.clearing;
      _failureKey = null;
    });
    _scrollToTop();
    OfflinePiiWorkspaceDeletionResult cleanup;
    try {
      cleanup = await widget.appSession.clearOrganizationOfflinePii(
        expectedAppUserId: _appUserId!,
        organizationWorkspaceId: organization.organizationWorkspaceId,
      );
    } catch (_) {
      cleanup = OfflinePiiWorkspaceDeletionResult.unavailable;
    }
    if (!_accepts(generation)) return;
    if (cleanup != OfflinePiiWorkspaceDeletionResult.deleted &&
        cleanup != OfflinePiiWorkspaceDeletionResult.notPresent) {
      setState(() {
        _stage = _RequestStage.ready;
        _failureKey = 'organizationDeletionRequestCacheClearFailed';
      });
      _scrollToTop();
      return;
    }

    setState(() => _stage = _RequestStage.submitting);
    OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>
    result;
    try {
      result = await widget.gateway.requestDeletion(
        requestId: _requestId!,
        organizationWorkspaceId: organization.organizationWorkspaceId,
      );
    } catch (_) {
      result = const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationDeletionRecoverySuccess(:final value):
        setState(() {
          _receipt = value;
          _failureKey = null;
          _uncertain = false;
          _stage = _RequestStage.succeeded;
        });
      case OrganizationDeletionRecoveryRejected(:final code):
        if (code == OrganizationDeletionRecoveryFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _stage = _RequestStage.ready;
          _failureKey = 'organizationDeletionRequestFailure.${code.name}';
          _uncertain |= _isUncertain(code);
        });
        _scrollToTop();
    }
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _RequestStage.sessionExpired &&
      _appUserId != null &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _appUserId &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _hasTrustedSession() =>
      _stage != _RequestStage.sessionExpired &&
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
    if (!mounted || _stage == _RequestStage.sessionExpired) return;
    _generation++;
    setState(() {
      _stage = _RequestStage.sessionExpired;
      _organization = null;
      _receipt = null;
      _appUserId = null;
      _requestId = null;
      _failureKey = null;
      _uncertain = false;
      _confirmDiscard = false;
    });
    _scrollToTop();
  }

  void _requestClose() {
    if (_busy) return;
    if (_confirmDiscard) {
      setState(() => _confirmDiscard = false);
    } else if (_uncertain) {
      setState(() => _confirmDiscard = true);
      _scrollToTop();
    } else {
      _close();
    }
  }

  void _close() => Navigator.of(context).pop(_receipt);

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  static bool _isUncertain(OrganizationDeletionRecoveryFailureCode code) =>
      switch (code) {
        OrganizationDeletionRecoveryFailureCode.serviceUnavailable ||
        OrganizationDeletionRecoveryFailureCode.networkUnavailable ||
        OrganizationDeletionRecoveryFailureCode.invalidResponse => true,
        _ => false,
      };
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
