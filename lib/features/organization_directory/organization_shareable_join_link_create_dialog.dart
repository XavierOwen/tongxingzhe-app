import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_directory/organization_directory.dart';
import '../../organization_shareable_join/organization_shareable_join.dart';

/// 为选定组织创建可分享加入链接。
///
/// 提交后所有重试都保留同一 organization 和 link UUID。Gateway 和
/// [AppSession] 的生命周期仍由 composition root 管理。
final class OrganizationShareableJoinLinkCreateDialog extends StatefulWidget {
  const OrganizationShareableJoinLinkCreateDialog({
    super.key,
    required this.text,
    required this.organization,
    required this.gateway,
    required this.appSession,
    this.linkIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationDirectoryEntry organization;
  final OrganizationShareableJoinGateway gateway;
  final AppSession appSession;
  final String Function() linkIdGenerator;

  @override
  State<OrganizationShareableJoinLinkCreateDialog> createState() =>
      _OrganizationShareableJoinLinkCreateDialogState();
}

enum _CreateLinkStage { ready, submitting, succeeded, sessionExpired }

final class _OrganizationShareableJoinLinkCreateDialogState
    extends State<OrganizationShareableJoinLinkCreateDialog> {
  final _scrollController = ScrollController();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;

  String? _appUserId;
  String? _linkId;
  OrganizationShareableJoinLinkCreateReceipt? _receipt;
  String? _failureKey;
  String? _copyStatusKey;
  var _stage = _CreateLinkStage.ready;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _copying = false;
  var _generation = 0;

  bool get _busy => _stage == _CreateLinkStage.submitting || _copying;

  @override
  void initState() {
    super.initState();
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _CreateLinkStage.sessionExpired;
    }
    _sessionSubscription = widget.appSession.changes.listen((snapshot) {
      if (!_isTrustedSnapshot(snapshot)) _invalidateSession();
    });
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
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
        key: const ValueKey('organization-shareable-link-create-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(
          widget.text.t(
            _confirmDiscard
                ? 'organizationShareableLinkCreateDiscardTitle'
                : 'organizationShareableLinkCreateTitle',
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
      return Text(widget.text.t('organizationShareableLinkCreateDiscardBody'));
    }

    final statusKey = switch (_stage) {
      _CreateLinkStage.submitting =>
        'organizationShareableLinkCreateSubmitting',
      _CreateLinkStage.succeeded => 'organizationShareableLinkCreateSuccess',
      _CreateLinkStage.sessionExpired =>
        'organizationShareableLinkCreateUnauthorized',
      _CreateLinkStage.ready => _failureKey,
    };
    final receipt = _receipt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-shareable-link-create-uncertain'),
            liveRegion: true,
            child: Text(
              widget.text.t('organizationShareableLinkCreateUncertain'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-shareable-link-create-status'),
            liveRegion: true,
            child: Text(widget.text.t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_copyStatusKey case final copyStatusKey?) ...[
          Semantics(
            key: const ValueKey(
              'organization-shareable-link-create-copy-status',
            ),
            liveRegion: true,
            child: Text(widget.text.t(copyStatusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_stage != _CreateLinkStage.sessionExpired) ...[
          Semantics(
            header: true,
            child: SelectableText(
              widget.organization.organizationName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.text.t('organizationShareableLinkCreateOrganizationId')),
          const SizedBox(height: 4),
          SelectableText(widget.organization.organizationWorkspaceId),
          const SizedBox(height: 16),
          if (receipt == null) ...[
            Text(widget.text.t('organizationShareableLinkCreateOwnerHelp')),
            const SizedBox(height: 12),
            Text(widget.text.t('organizationShareableLinkCreateDeliveryHelp')),
          ] else ...[
            Text(widget.text.t('organizationShareableLinkCreateLinkId')),
            const SizedBox(height: 4),
            SelectableText(receipt.linkId),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationShareableLinkCreateIssuedAt')),
            const SizedBox(height: 4),
            SelectableText(receipt.issuedAtUtc.toUtc().toIso8601String()),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationShareableLinkCreateExpiresAt')),
            const SizedBox(height: 4),
            SelectableText(receipt.expiresAtUtc.toUtc().toIso8601String()),
            const SizedBox(height: 16),
            Text(widget.text.t('organizationShareableLinkCreateNoUrl')),
            const SizedBox(height: 12),
            Text(
              widget.text.t('organizationShareableLinkCreateFreshnessNotice'),
            ),
          ],
        ],
      ],
    );
  }

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-shareable-link-create-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(
            widget.text.t('organizationShareableLinkCreateKeepRetry'),
          ),
        ),
        FilledButton(
          key: const ValueKey('organization-shareable-link-create-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationShareableLinkCreateDiscard')),
        ),
      ];
    }

    return [
      TextButton(
        key: const ValueKey('organization-shareable-link-create-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationShareableLinkCreateClose')),
      ),
      if (_stage == _CreateLinkStage.succeeded)
        FilledButton.icon(
          key: const ValueKey('organization-shareable-link-create-copy'),
          onPressed: _busy ? null : _copyLinkId,
          icon: const Icon(Icons.copy_outlined),
          label: Text(widget.text.t('organizationShareableLinkCreateCopy')),
        )
      else if (_stage != _CreateLinkStage.sessionExpired)
        FilledButton(
          key: const ValueKey('organization-shareable-link-create-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(
            widget.text.t(
              _linkId == null
                  ? 'organizationShareableLinkCreateSubmit'
                  : 'organizationShareableLinkCreateRetry',
            ),
          ),
        ),
    ];
  }

  Future<void> _submit() async {
    if (_stage != _CreateLinkStage.ready ||
        _busy ||
        _confirmDiscard ||
        !_checkSession()) {
      return;
    }

    if (_linkId == null) {
      try {
        final generated = widget.linkIdGenerator().toLowerCase();
        if (!_canonicalUuidPattern.hasMatch(generated)) {
          throw const FormatException();
        }
        _linkId = generated;
      } catch (_) {
        setState(() {
          _failureKey = 'organizationShareableLinkCreateInvalidRequest';
          _copyStatusKey = null;
        });
        _scrollToStatus();
        return;
      }
    }

    final linkId = _linkId!;
    final generation = ++_generation;
    setState(() {
      _stage = _CreateLinkStage.submitting;
      _failureKey = null;
      _copyStatusKey = null;
    });
    _scrollToStatus();

    OrganizationShareableJoinLinkCreateResult result;
    try {
      result = await widget.gateway.createLink(
        linkId: linkId,
        organizationWorkspaceId: widget.organization.organizationWorkspaceId,
      );
    } catch (_) {
      result = const OrganizationShareableJoinLinkCreateRejected(
        OrganizationShareableJoinFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;

    switch (result) {
      case OrganizationShareableJoinLinkCreateSuccess(:final receipt):
        setState(() {
          _receipt = receipt;
          _stage = _CreateLinkStage.succeeded;
          _failureKey = null;
          _uncertain = false;
        });
      case OrganizationShareableJoinLinkCreateRejected(:final code):
        if (code == OrganizationShareableJoinFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        final uncertain = _uncertain || _isUncertain(code);
        setState(() {
          _stage = _CreateLinkStage.ready;
          _failureKey = 'organizationShareableLinkCreateFailure.${code.name}';
          _uncertain = uncertain;
        });
    }
    _scrollToStatus();
  }

  Future<void> _copyLinkId() async {
    final receipt = _receipt;
    if (_busy || receipt == null || !_checkSession()) return;
    final generation = ++_generation;
    setState(() {
      _copying = true;
      _copyStatusKey = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: receipt.linkId));
      if (!_accepts(generation)) return;
      setState(() {
        _copying = false;
        _copyStatusKey = 'organizationShareableLinkCreateCopySuccess';
      });
    } catch (_) {
      if (!_accepts(generation)) return;
      setState(() {
        _copying = false;
        _copyStatusKey = 'organizationShareableLinkCreateCopyFailure';
      });
    }
    _scrollToStatus();
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _CreateLinkStage.sessionExpired &&
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
    if (!mounted || _stage == _CreateLinkStage.sessionExpired) return;
    _generation += 1;
    setState(() {
      _stage = _CreateLinkStage.sessionExpired;
      _linkId = null;
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

  static bool _isUncertain(OrganizationShareableJoinFailureCode code) =>
      switch (code) {
        OrganizationShareableJoinFailureCode.conflict ||
        OrganizationShareableJoinFailureCode.serviceUnavailable ||
        OrganizationShareableJoinFailureCode.networkUnavailable ||
        OrganizationShareableJoinFailureCode.invalidResponse => true,
        _ => false,
      };
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
