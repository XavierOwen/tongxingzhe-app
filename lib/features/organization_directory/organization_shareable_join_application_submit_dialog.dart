import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_shareable_join/organization_shareable_join.dart';

/// 预览可分享加入链接，由用户明确确认后提交入组申请。
final class OrganizationShareableJoinApplicationSubmitDialog
    extends StatefulWidget {
  const OrganizationShareableJoinApplicationSubmitDialog({
    super.key,
    required this.text,
    required this.gateway,
    required this.appSession,
    this.applicationIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationShareableJoinGateway gateway;
  final AppSession appSession;
  final String Function() applicationIdGenerator;

  @override
  State<OrganizationShareableJoinApplicationSubmitDialog> createState() =>
      _OrganizationShareableJoinApplicationSubmitDialogState();
}

enum _ApplicationStage {
  entering,
  previewing,
  confirming,
  submitting,
  succeeded,
  sessionExpired,
}

final class _OrganizationShareableJoinApplicationSubmitDialogState
    extends State<OrganizationShareableJoinApplicationSubmitDialog> {
  final _linkController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;

  String? _appUserId;
  String? _linkId;
  String? _applicationId;
  OrganizationShareableJoinLinkPreviewReceipt? _preview;
  OrganizationShareableJoinApplicationSubmitReceipt? _receipt;
  String? _failureKey;
  String? _copyStatusKey;
  var _stage = _ApplicationStage.entering;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _copying = false;
  var _generation = 0;

  bool get _busy =>
      _stage == _ApplicationStage.previewing ||
      _stage == _ApplicationStage.submitting ||
      _copying;

  @override
  void initState() {
    super.initState();
    final snapshot = widget.appSession.current;
    _appUserId = snapshot.context?.appUserId;
    if (!_isTrustedSnapshot(snapshot)) {
      _stage = _ApplicationStage.sessionExpired;
    }
    _sessionSubscription = widget.appSession.changes.listen((snapshot) {
      if (!_isTrustedSnapshot(snapshot)) _invalidateSession();
    });
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_sessionSubscription?.cancel());
    _linkController.dispose();
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
        key: const ValueKey('organization-shareable-application-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(
          widget.text.t(
            _confirmDiscard
                ? 'organizationShareableApplicationDiscardTitle'
                : 'organizationShareableApplicationTitle',
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
      return Text(widget.text.t('organizationShareableApplicationDiscardBody'));
    }

    final statusKey = switch (_stage) {
      _ApplicationStage.previewing =>
        'organizationShareableApplicationPreviewing',
      _ApplicationStage.submitting =>
        'organizationShareableApplicationSubmitting',
      _ApplicationStage.succeeded => 'organizationShareableApplicationSuccess',
      _ApplicationStage.sessionExpired =>
        'organizationShareableApplicationUnauthorized',
      _ => _failureKey,
    };
    final preview = _preview;
    final receipt = _receipt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_uncertain) ...[
          Semantics(
            key: const ValueKey('organization-shareable-application-uncertain'),
            liveRegion: true,
            child: Text(
              widget.text.t('organizationShareableApplicationUncertain'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (statusKey != null) ...[
          Semantics(
            key: const ValueKey('organization-shareable-application-status'),
            liveRegion: true,
            child: Text(widget.text.t(statusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_copyStatusKey case final copyStatusKey?) ...[
          Semantics(
            key: const ValueKey(
              'organization-shareable-application-copy-status',
            ),
            liveRegion: true,
            child: Text(widget.text.t(copyStatusKey)),
          ),
          const SizedBox(height: 16),
        ],
        if (_stage != _ApplicationStage.sessionExpired)
          if (receipt != null && preview != null) ...[
            Semantics(
              header: true,
              child: SelectableText(
                preview.organizationName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            _value(
              'organizationShareableApplicationApplicationId',
              receipt.applicationId,
            ),
            _value('organizationShareableApplicationLinkId', receipt.linkId),
            _value(
              'organizationShareableApplicationOrganizationId',
              receipt.organizationWorkspaceId,
            ),
            _value(
              'organizationShareableApplicationSubmittedAt',
              receipt.submittedAtUtc.toUtc().toIso8601String(),
            ),
            _value(
              'organizationShareableApplicationExpiresAt',
              receipt.expiresAtUtc.toUtc().toIso8601String(),
            ),
            Text(widget.text.t('organizationShareableApplicationDeliveryHelp')),
            const SizedBox(height: 12),
            Text(
              widget.text.t('organizationShareableApplicationFreshnessNotice'),
            ),
          ] else if (preview != null) ...[
            Semantics(
              header: true,
              child: SelectableText(
                preview.organizationName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            _value('organizationShareableApplicationLinkId', preview.linkId),
            _value(
              'organizationShareableApplicationExpiresAt',
              preview.expiresAtUtc.toUtc().toIso8601String(),
            ),
            Text(widget.text.t('organizationShareableApplicationConfirmHelp')),
          ] else ...[
            Text(widget.text.t('organizationShareableApplicationInputHelp')),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey(
                'organization-shareable-application-link-field',
              ),
              controller: _linkController,
              enabled: !_busy,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.text.t(
                  'organizationShareableApplicationLinkIdentifier',
                ),
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
          key: const ValueKey('organization-shareable-application-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(
            widget.text.t('organizationShareableApplicationKeepRetry'),
          ),
        ),
        FilledButton(
          key: const ValueKey('organization-shareable-application-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationShareableApplicationDiscard')),
        ),
      ];
    }

    return [
      TextButton(
        key: const ValueKey('organization-shareable-application-close'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('organizationShareableApplicationClose')),
      ),
      if (_preview != null &&
          _applicationId == null &&
          _stage != _ApplicationStage.succeeded)
        TextButton(
          key: const ValueKey('organization-shareable-application-edit'),
          onPressed: _busy ? null : _editLink,
          child: Text(widget.text.t('organizationShareableApplicationEdit')),
        ),
      if (_stage == _ApplicationStage.succeeded)
        FilledButton.icon(
          key: const ValueKey('organization-shareable-application-copy'),
          onPressed: _busy ? null : _copyApplicationId,
          icon: const Icon(Icons.copy_outlined),
          label: Text(widget.text.t('organizationShareableApplicationCopy')),
        )
      else if (_stage != _ApplicationStage.sessionExpired)
        FilledButton(
          key: ValueKey(
            _preview == null
                ? 'organization-shareable-application-preview'
                : 'organization-shareable-application-submit',
          ),
          onPressed: _busy
              ? null
              : _preview == null
              ? _loadPreview
              : _submitApplication,
          child: Text(
            widget.text.t(
              _preview == null
                  ? 'organizationShareableApplicationPreview'
                  : _applicationId == null
                  ? 'organizationShareableApplicationSubmit'
                  : 'organizationShareableApplicationRetry',
            ),
          ),
        ),
    ];
  }

  Future<void> _loadPreview() async {
    if (_busy || _applicationId != null || !_checkSession()) return;
    final linkId = _linkController.text.trim().toLowerCase();
    if (!_canonicalUuidPattern.hasMatch(linkId)) {
      setState(
        () => _failureKey = 'organizationShareableApplicationInvalidLink',
      );
      _scrollToStatus();
      return;
    }

    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _linkId = linkId;
      _preview = null;
      _failureKey = null;
      _copyStatusKey = null;
      _stage = _ApplicationStage.previewing;
    });
    _scrollToStatus();

    OrganizationShareableJoinLinkPreviewResult result;
    try {
      result = await widget.gateway.previewLink(linkId: linkId);
    } catch (_) {
      result = const OrganizationShareableJoinLinkPreviewRejected(
        OrganizationShareableJoinFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;

    switch (result) {
      case OrganizationShareableJoinLinkPreviewSuccess(:final receipt):
        setState(() {
          _preview = receipt;
          _stage = _ApplicationStage.confirming;
        });
      case OrganizationShareableJoinLinkPreviewRejected(:final code):
        if (code == OrganizationShareableJoinFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _stage = _ApplicationStage.entering;
          _failureKey =
              'organizationShareableApplicationPreviewFailure.${code.name}';
        });
    }
    _scrollToStatus();
  }

  Future<void> _submitApplication() async {
    final preview = _preview;
    if (_busy || preview == null || !_checkSession()) return;

    if (_applicationId == null) {
      try {
        final generated = widget.applicationIdGenerator().toLowerCase();
        if (!_canonicalUuidPattern.hasMatch(generated)) {
          throw const FormatException();
        }
        _applicationId = generated;
      } catch (_) {
        setState(() {
          _failureKey = 'organizationShareableApplicationInvalidRequest';
          _copyStatusKey = null;
        });
        _scrollToStatus();
        return;
      }
    }

    final applicationId = _applicationId!;
    final linkId = _linkId!;
    final generation = ++_generation;
    setState(() {
      _stage = _ApplicationStage.submitting;
      _failureKey = null;
      _copyStatusKey = null;
    });
    _scrollToStatus();

    OrganizationShareableJoinApplicationSubmitResult result;
    try {
      result = await widget.gateway.submitApplication(
        applicationId: applicationId,
        linkId: linkId,
      );
    } catch (_) {
      result = const OrganizationShareableJoinApplicationSubmitRejected(
        OrganizationShareableJoinFailureCode.invalidResponse,
      );
    }
    if (!_accepts(generation)) return;

    switch (result) {
      case OrganizationShareableJoinApplicationSubmitSuccess(:final receipt):
        setState(() {
          _receipt = receipt;
          _stage = _ApplicationStage.succeeded;
          _failureKey = null;
          _uncertain = false;
        });
      case OrganizationShareableJoinApplicationSubmitRejected(:final code):
        if (code == OrganizationShareableJoinFailureCode.unauthorized) {
          _invalidateSession();
          return;
        }
        setState(() {
          _stage = _ApplicationStage.confirming;
          _failureKey =
              'organizationShareableApplicationSubmitFailure.${code.name}';
          _uncertain = _isUncertain(code);
        });
    }
    _scrollToStatus();
  }

  Future<void> _copyApplicationId() async {
    final receipt = _receipt;
    if (_busy || receipt == null || !_checkSession()) return;
    final generation = ++_generation;
    setState(() {
      _copying = true;
      _copyStatusKey = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: receipt.applicationId));
      if (!_accepts(generation)) return;
      setState(() {
        _copying = false;
        _copyStatusKey = 'organizationShareableApplicationCopySuccess';
      });
    } catch (_) {
      if (!_accepts(generation)) return;
      setState(() {
        _copying = false;
        _copyStatusKey = 'organizationShareableApplicationCopyFailure';
      });
    }
    _scrollToStatus();
  }

  void _editLink() {
    if (_busy || _applicationId != null || !_checkSession()) return;
    setState(() {
      _preview = null;
      _linkId = null;
      _failureKey = null;
      _stage = _ApplicationStage.entering;
    });
    _scrollToStatus();
  }

  bool _isTrustedSnapshot(AppSessionSnapshot snapshot) =>
      _stage != _ApplicationStage.sessionExpired &&
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
    if (!mounted || _stage == _ApplicationStage.sessionExpired) return;
    _generation += 1;
    setState(() {
      _stage = _ApplicationStage.sessionExpired;
      _linkController.clear();
      _linkId = null;
      _applicationId = null;
      _preview = null;
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
        OrganizationShareableJoinFailureCode.serviceUnavailable ||
        OrganizationShareableJoinFailureCode.networkUnavailable ||
        OrganizationShareableJoinFailureCode.invalidResponse => true,
        _ => false,
      };
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
