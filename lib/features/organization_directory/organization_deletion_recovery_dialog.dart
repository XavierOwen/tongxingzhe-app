import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_deletion_recovery/organization_deletion_recovery.dart';

/// Shows the short-lived owner recovery directory and confirms one restore.
final class OrganizationDeletionRecoveryDialog extends StatefulWidget {
  const OrganizationDeletionRecoveryDialog({
    super.key,
    required this.text,
    required this.gateway,
    required this.appSession,
    this.onRestored,
    this.requestIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationDeletionRecoveryGateway gateway;
  final AppSession appSession;
  final Future<void> Function()? onRestored;
  final String Function() requestIdGenerator;

  @override
  State<OrganizationDeletionRecoveryDialog> createState() =>
      _OrganizationDeletionRecoveryDialogState();
}

enum _RecoveryStage {
  loading,
  browsing,
  confirming,
  submitting,
  uncertain,
  failed,
  succeeded,
  sessionExpired,
}

final class _OrganizationDeletionRecoveryDialogState
    extends State<OrganizationDeletionRecoveryDialog> {
  final _scrollController = ScrollController();
  final _dialogFocus = FocusNode();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;
  List<OrganizationDeletionRecoveryItem> _items = const [];
  OrganizationDeletionRecoveryItem? _selected;
  OrganizationRestorationReceipt? _receipt;
  OrganizationDeletionRecoveryFailureCode? _failure;
  String? _appUserId;
  String? _requestId;
  var _stage = _RecoveryStage.loading;
  var _generation = 0;
  var _confirmDiscard = false;
  var _directoryRefreshStarted = false;

  bool get _busy =>
      _stage == _RecoveryStage.loading || _stage == _RecoveryStage.submitting;
  bool get _uncertain => _stage == _RecoveryStage.uncertain;

  @override
  void initState() {
    super.initState();
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _RecoveryStage.sessionExpired;
      _appUserId = null;
    }
    _sessionSubscription = widget.appSession.changes.listen(
      (snapshot) {
        if (!_isTrustedSnapshot(snapshot)) _invalidateSession();
      },
      onError: (Object _, StackTrace _) => _invalidateSession(),
      onDone: _invalidateSession,
    );
    if (_stage != _RecoveryStage.sessionExpired) unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_sessionSubscription?.cancel());
    _scrollController.dispose();
    _dialogFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_busy && !_uncertain && !_confirmDiscard,
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
        key: const ValueKey('organization-deletion-recovery-dialog'),
        insetPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 24,
        ),
        constraints: const BoxConstraints(maxWidth: 560),
        title: Semantics(
          header: true,
          namesRoute: true,
          child: Text(
            widget.text.t(
              _confirmDiscard
                  ? 'organizationDeletionRecoveryDiscardTitle'
                  : _selected != null && _stage != _RecoveryStage.succeeded
                  ? 'organizationDeletionRecoveryConfirmTitle'
                  : 'organizationDeletionRecoveryTitle',
            ),
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
      return Text(widget.text.t('organizationDeletionRecoveryDiscardBody'));
    }
    final status = _statusText;
    if (_stage == _RecoveryStage.sessionExpired) {
      return Semantics(
        key: const ValueKey('organization-deletion-recovery-status'),
        liveRegion: true,
        child: Text(widget.text.t('organizationDeletionRecoveryUnauthorized')),
      );
    }
    if (_stage == _RecoveryStage.succeeded) {
      final receipt = _receipt;
      if (receipt == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _liveStatus(status),
          const SizedBox(height: 16),
          _value(
            'organizationDeletionRecoveryWorkspaceId',
            receipt.organizationWorkspaceId,
          ),
          _value(
            'organizationDeletionRecoveryDeletionRequestId',
            receipt.deletionRequestId,
          ),
          _value(
            'organizationDeletionRecoveryRestoredAt',
            receipt.restoredAtUtc,
          ),
          Text(widget.text.t('organizationDeletionRecoverySuccessNotice')),
        ],
      );
    }

    final selected = _selected;
    if (selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.text.t('organizationDeletionRecoveryHelp')),
          const SizedBox(height: 16),
          _organizationDetails(selected),
          if (_uncertain) ...[
            const SizedBox(height: 8),
            _liveStatus(widget.text.t('organizationDeletionRecoveryUncertain')),
          ] else if (_failure != null) ...[
            const SizedBox(height: 8),
            _liveStatus(_failureText(_failure!)),
          ],
          if (_stage == _RecoveryStage.confirming || _uncertain) ...[
            const SizedBox(height: 8),
            Text(widget.text.t('organizationDeletionRecoveryConfirmHelp')),
          ],
          if (_stage == _RecoveryStage.submitting) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            _liveStatus(status),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.text.t('organizationDeletionRecoveryHelp')),
        const SizedBox(height: 16),
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _liveStatus(status),
        ] else ...[
          _liveStatus(status),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var index = 0; index < _items.length; index++) ...[
              if (index > 0) const Divider(),
              _itemRow(_items[index]),
            ],
          ],
        ],
      ],
    );
  }

  Widget _itemRow(OrganizationDeletionRecoveryItem item) => Padding(
    key: ValueKey('organization-recovery-item-${item.organizationWorkspaceId}'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            item.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        _value(
          'organizationDeletionRecoveryWorkspaceId',
          item.organizationWorkspaceId,
        ),
        _value('organizationDeletionRecoveryDeadline', item.purgeAfterUtc),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: ValueKey(
              'organization-recovery-restore-${item.organizationWorkspaceId}',
            ),
            onPressed: _stage == _RecoveryStage.browsing
                ? () => _select(item)
                : null,
            icon: const Icon(Icons.restore_outlined),
            label: Text(
              widget.text.t('organizationDeletionRecoveryRestoreAction'),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _organizationDetails(OrganizationDeletionRecoveryItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(
          item.displayName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      _value(
        'organizationDeletionRecoveryWorkspaceId',
        item.organizationWorkspaceId,
      ),
      _value(
        'organizationDeletionRecoveryDeletionRequestId',
        item.deletionRequestId,
      ),
      _value('organizationDeletionRecoveryDeadline', item.purgeAfterUtc),
    ],
  );

  Widget _value(String labelKey, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.text.t(labelKey)),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );

  Widget _liveStatus(String label) => Semantics(
    key: const ValueKey('organization-deletion-recovery-status'),
    liveRegion: true,
    child: Text(label),
  );

  String get _statusText => switch (_stage) {
    _RecoveryStage.loading => widget.text.t(
      'organizationDeletionRecoveryLoading',
    ),
    _RecoveryStage.browsing =>
      _failure == null
          ? _items.isEmpty
                ? widget.text.t('organizationDeletionRecoveryEmpty')
                : widget.text.t('organizationDeletionRecoveryLoaded')
          : _failureText(_failure!),
    _RecoveryStage.confirming => '',
    _RecoveryStage.submitting => widget.text.t(
      'organizationDeletionRecoverySubmitting',
    ),
    _RecoveryStage.uncertain => widget.text.t(
      'organizationDeletionRecoveryUncertain',
    ),
    _RecoveryStage.failed => _failure == null ? '' : _failureText(_failure!),
    _RecoveryStage.succeeded => widget.text.t(
      'organizationDeletionRecoverySuccess',
    ),
    _RecoveryStage.sessionExpired => widget.text.t(
      'organizationDeletionRecoveryUnauthorized',
    ),
  };

  String _failureText(OrganizationDeletionRecoveryFailureCode code) =>
      widget.text.t('organizationDeletionRecoveryFailure.${code.name}');

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-deletion-recovery-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationDeletionRecoveryKeepRetry')),
        ),
        FilledButton(
          key: const ValueKey('organization-deletion-recovery-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationDeletionRecoveryDiscard')),
        ),
      ];
    }
    if (_stage == _RecoveryStage.succeeded) {
      return [
        FilledButton(
          key: const ValueKey('organization-deletion-recovery-done'),
          onPressed: _close,
          child: Text(widget.text.t('organizationDeletionRecoveryClose')),
        ),
      ];
    }
    final selected = _selected;
    return [
      TextButton(
        key: const ValueKey('organization-deletion-recovery-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationDeletionRecoveryClose')),
      ),
      if (_stage == _RecoveryStage.browsing || _stage == _RecoveryStage.failed)
        TextButton(
          key: const ValueKey('organization-deletion-recovery-refresh'),
          onPressed: _busy || _stage == _RecoveryStage.failed ? null : _load,
          child: Text(widget.text.t('organizationDeletionRecoveryRefresh')),
        ),
      if (_stage == _RecoveryStage.confirming && selected != null)
        TextButton(
          key: const ValueKey('organization-deletion-recovery-cancel'),
          onPressed: _cancelSelection,
          child: Text(widget.text.t('organizationDeletionRecoveryCancel')),
        ),
      if (_stage == _RecoveryStage.confirming || _uncertain)
        FilledButton(
          key: const ValueKey('organization-deletion-recovery-confirm'),
          onPressed: _busy ? null : _restore,
          child: Text(
            widget.text.t(
              _uncertain
                  ? 'organizationDeletionRecoveryRetry'
                  : 'organizationDeletionRecoveryConfirm',
            ),
          ),
        ),
      if (_stage == _RecoveryStage.failed)
        FilledButton(
          key: const ValueKey('organization-deletion-recovery-back-to-list'),
          onPressed: _backToList,
          child: Text(widget.text.t('organizationDeletionRecoveryBackToList')),
        ),
    ];
  }

  void _select(OrganizationDeletionRecoveryItem item) {
    if (_stage != _RecoveryStage.browsing || !_checkSession()) return;
    setState(() {
      _selected = item;
      _requestId = null;
      _failure = null;
      _stage = _RecoveryStage.confirming;
    });
    _scrollToTop();
  }

  void _cancelSelection() {
    if (_stage != _RecoveryStage.confirming || !_checkSession()) return;
    setState(() {
      _selected = null;
      _requestId = null;
      _failure = null;
      _stage = _RecoveryStage.browsing;
    });
  }

  void _backToList() {
    if (_stage != _RecoveryStage.failed || !_checkSession()) return;
    setState(() {
      _selected = null;
      _requestId = null;
      _failure = null;
      _stage = _RecoveryStage.browsing;
    });
  }

  Future<void> _load() async {
    if (_stage == _RecoveryStage.submitting || !_checkSession()) return;
    final generation = ++_generation;
    setState(() {
      _stage = _RecoveryStage.loading;
      _items = const [];
      _selected = null;
      _requestId = null;
      _receipt = null;
      _failure = null;
    });
    OrganizationDeletionRecoveryResult<OrganizationDeletionRecoveryDirectory>
    result;
    try {
      result = await widget.gateway.listRecoverableOrganizations();
    } catch (_) {
      result = const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationDeletionRecoverySuccess(:final value):
        setState(() {
          _items = value.items;
          _stage = _RecoveryStage.browsing;
        });
      case OrganizationDeletionRecoveryRejected(:final code):
        if (code == OrganizationDeletionRecoveryFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _failure = code;
          _stage = _RecoveryStage.browsing;
        });
    }
  }

  Future<void> _restore() async {
    final selected = _selected;
    if ((_stage != _RecoveryStage.confirming && !_uncertain) ||
        selected == null ||
        !_checkSession()) {
      return;
    }
    if (_requestId == null) {
      try {
        final generated = widget.requestIdGenerator().toLowerCase();
        if (!_uuidPattern.hasMatch(generated)) throw const FormatException();
        _requestId = generated;
      } catch (_) {
        setState(() {
          _failure = OrganizationDeletionRecoveryFailureCode.invalidRequest;
          _stage = _RecoveryStage.failed;
        });
        _scrollToTop();
        return;
      }
    }
    final requestId = _requestId!;
    final generation = ++_generation;
    setState(() {
      _failure = null;
      _stage = _RecoveryStage.submitting;
    });
    OrganizationDeletionRecoveryResult<OrganizationRestorationReceipt> result;
    try {
      result = await widget.gateway.restore(
        requestId: requestId,
        organizationWorkspaceId: selected.organizationWorkspaceId,
        deletionRequestId: selected.deletionRequestId,
      );
    } catch (_) {
      result = const OrganizationDeletionRecoveryRejected(
        OrganizationDeletionRecoveryFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;
    switch (result) {
      case OrganizationDeletionRecoverySuccess(:final value):
        if (!_directoryRefreshStarted) {
          _directoryRefreshStarted = true;
          try {
            await widget.onRestored?.call();
          } catch (_) {
            // The restore receipt is authoritative even if the parent refresh fails.
          }
        }
        if (!_accepts(generation)) return;
        setState(() {
          _receipt = value;
          _failure = null;
          _stage = _RecoveryStage.succeeded;
        });
      case OrganizationDeletionRecoveryRejected(:final code):
        if (code == OrganizationDeletionRecoveryFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _failure = code;
          _stage = _isUncertain(code)
              ? _RecoveryStage.uncertain
              : _RecoveryStage.failed;
        });
    }
    _scrollToTop();
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _RecoveryStage.sessionExpired &&
      _appUserId != null &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _appUserId &&
      widget.appSession.isCurrentUser(_appUserId!);

  bool _checkSession() {
    if (_isTrustedSnapshot(widget.appSession.current)) return true;
    _invalidateSession();
    return false;
  }

  bool _accepts(int generation) =>
      mounted && generation == _generation && _checkSession();

  void _invalidateSession() {
    if (!mounted || _stage == _RecoveryStage.sessionExpired) return;
    _generation++;
    setState(() {
      _stage = _RecoveryStage.sessionExpired;
      _items = const [];
      _selected = null;
      _receipt = null;
      _failure = null;
      _appUserId = null;
      _requestId = null;
      _confirmDiscard = false;
    });
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

  void _close() => Navigator.of(context).pop();

  void _scrollToTop() {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  static bool _isUncertain(OrganizationDeletionRecoveryFailureCode code) =>
      switch (code) {
        OrganizationDeletionRecoveryFailureCode.networkUnavailable ||
        OrganizationDeletionRecoveryFailureCode.serviceUnavailable ||
        OrganizationDeletionRecoveryFailureCode.invalidResponse => true,
        _ => false,
      };
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
