import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directory/organization_directory.dart';
import '../../organization_owner_transfer/organization_owner_transfer.dart';

/// 核对已知组织成员关系 UUID 后，原子交接当前账号的组织所有权。
final class OrganizationOwnerTransferDialog extends StatefulWidget {
  const OrganizationOwnerTransferDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
    this.requestIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationOwnerTransferGateway gateway;
  final AppSession appSession;
  final String Function() requestIdGenerator;

  @override
  State<OrganizationOwnerTransferDialog> createState() =>
      _OrganizationOwnerTransferDialogState();
}

enum _TransferStage {
  entering,
  confirming,
  submitting,
  succeeded,
  sessionExpired,
}

final class _OrganizationOwnerTransferDialogState
    extends State<OrganizationOwnerTransferDialog> {
  final _targetController = TextEditingController();
  final _scrollController = ScrollController();
  final _dialogFocus = FocusNode();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  OrganizationDirectoryEntry? _organization;
  String? _appUserId;
  String? _targetMembershipId;
  String? _requestId;
  OrganizationOwnerTransferReceipt? _receipt;
  String? _failureKey;
  var _stage = _TransferStage.entering;
  var _submitted = false;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _generation = 0;

  bool get _busy => _stage == _TransferStage.submitting;

  @override
  void initState() {
    super.initState();
    _organization = widget.organization;
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _TransferStage.sessionExpired;
      _organization = null;
      _appUserId = null;
    }
    _sessionSubscription = widget.appSession.changes.listen((snapshot) {
      if (!_isTrustedSnapshot(snapshot)) _invalidateSession();
    });
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
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
        key: const ValueKey('organization-owner-transfer-dialog'),
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
                          ? 'organizationOwnerTransferDiscardTitle'
                          : 'organizationOwnerTransferTitle',
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
      return Text(widget.text.t('organizationOwnerTransferDiscardBody'));
    }
    final statusKey = switch (_stage) {
      _TransferStage.submitting => 'organizationOwnerTransferSubmitting',
      _TransferStage.succeeded => 'organizationOwnerTransferSuccess',
      _TransferStage.sessionExpired => 'organizationOwnerTransferUnauthorized',
      _ => _failureKey,
    };
    final organization = _organization;
    final receipt = _receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-owner-transfer-uncertain'),
            liveRegion: true,
            child: Text(widget.text.t('organizationOwnerTransferUncertain')),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-owner-transfer-status'),
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
            'organizationOwnerTransferOrganizationId',
            receipt?.organizationWorkspaceId ??
                organization.organizationWorkspaceId,
          ),
          if (receipt != null) ...[
            _value(
              'organizationOwnerTransferTargetMembershipId',
              _targetMembershipId!,
            ),
            _value(
              'organizationOwnerTransferContractId',
              receipt.ownerTransferContractId,
            ),
            _value(
              'organizationOwnerTransferPreviousOwnerAssignmentId',
              receipt.previousOwnerAssignmentId,
            ),
            _value(
              'organizationOwnerTransferOwnerAssignmentId',
              receipt.organizationOwnerAssignmentId,
            ),
            _value(
              'organizationOwnerTransferEffectiveAt',
              receipt.effectiveAtUtc.toUtc().toIso8601String(),
            ),
            Text(widget.text.t('organizationOwnerTransferFreshnessNotice')),
          ] else if (_stage == _TransferStage.entering) ...[
            Text(widget.text.t('organizationOwnerTransferInputHelp')),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('organization-owner-transfer-target-field'),
              controller: _targetController,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.text.t(
                  'organizationOwnerTransferTargetMembershipIdentifier',
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
              'organizationOwnerTransferTargetMembershipId',
              _targetMembershipId!,
            ),
            Text(widget.text.t('organizationOwnerTransferConfirmHelp')),
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
          key: const ValueKey('organization-owner-transfer-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationOwnerTransferKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-owner-transfer-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationOwnerTransferDiscard')),
        ),
      ];
    }
    return [
      TextButton(
        key: const ValueKey('organization-owner-transfer-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationOwnerTransferClose')),
      ),
      if (_stage == _TransferStage.confirming && !_submitted)
        TextButton(
          key: const ValueKey('organization-owner-transfer-edit'),
          onPressed: _edit,
          child: Text(widget.text.t('organizationOwnerTransferEdit')),
        ),
      if (_stage != _TransferStage.succeeded &&
          _stage != _TransferStage.sessionExpired)
        FilledButton(
          key: ValueKey(
            _stage == _TransferStage.entering
                ? 'organization-owner-transfer-review'
                : 'organization-owner-transfer-submit',
          ),
          onPressed: _busy
              ? null
              : _stage == _TransferStage.entering
              ? _review
              : _transfer,
          child: Text(
            widget.text.t(
              _stage == _TransferStage.entering
                  ? 'organizationOwnerTransferReview'
                  : _submitted
                  ? 'organizationOwnerTransferRetry'
                  : 'organizationOwnerTransferTransfer',
            ),
          ),
        ),
    ];
  }

  void _review() {
    if (_stage != _TransferStage.entering ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    final targetOrganizationMembershipId = _targetController.text
        .trim()
        .toLowerCase();
    if (!_canonicalUuidPattern.hasMatch(targetOrganizationMembershipId)) {
      setState(
        () => _failureKey = 'organizationOwnerTransferInvalidTargetMembership',
      );
      _scrollToStatus();
      return;
    }
    FocusScope.of(context).unfocus();
    _dialogFocus.requestFocus();
    setState(() {
      _targetMembershipId = targetOrganizationMembershipId;
      _failureKey = null;
      _stage = _TransferStage.confirming;
    });
    _scrollToStatus();
  }

  void _edit() {
    if (_stage != _TransferStage.confirming ||
        _submitted ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }
    setState(() {
      _targetMembershipId = null;
      _failureKey = null;
      _stage = _TransferStage.entering;
    });
    _scrollToStatus();
  }

  Future<void> _transfer() async {
    if (_stage != _TransferStage.confirming ||
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
        setState(() => _failureKey = 'organizationOwnerTransferInvalidRequest');
        _scrollToStatus();
        return;
      }
    }
    final requestId = _requestId!;
    final targetOrganizationMembershipId = _targetMembershipId!;
    final organizationWorkspaceId = _organization!.organizationWorkspaceId;
    final generation = ++_generation;
    setState(() {
      _submitted = true;
      _stage = _TransferStage.submitting;
      _failureKey = null;
    });
    _scrollToStatus();
    OrganizationOwnerTransferResult result;
    try {
      result = await widget.gateway.transfer(
        requestId: requestId,
        organizationWorkspaceId: organizationWorkspaceId,
        targetOrganizationMembershipId: targetOrganizationMembershipId,
      );
    } catch (_) {
      result = const OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationOwnerTransferSuccess(:final receipt):
        setState(() {
          _receipt = receipt;
          _stage = _TransferStage.succeeded;
          _failureKey = null;
          _uncertain = false;
        });
      case OrganizationOwnerTransferRejected(:final code):
        if (code == OrganizationOwnerTransferFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _stage = _TransferStage.confirming;
          _failureKey = 'organizationOwnerTransferFailure.${code.name}';
          _uncertain = _isUncertain(code);
        });
    }
    _scrollToStatus();
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _TransferStage.sessionExpired &&
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
    if (!mounted || _stage == _TransferStage.sessionExpired) return;
    _generation += 1;
    setState(() {
      _stage = _TransferStage.sessionExpired;
      _targetController.clear();
      _organization = null;
      _appUserId = null;
      _targetMembershipId = null;
      _requestId = null;
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

  static bool _isUncertain(OrganizationOwnerTransferFailureCode code) =>
      switch (code) {
        OrganizationOwnerTransferFailureCode.networkUnavailable ||
        OrganizationOwnerTransferFailureCode.serviceUnavailable ||
        OrganizationOwnerTransferFailureCode.invalidResponse => true,
        _ => false,
      };
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
