import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_session/app_session.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../organization_creation/organization_creation.dart';

/// 创建私有组织，并在结果不确定时保留同一次幂等请求。
///
/// 成功时对话框返回 [OrganizationCreationReceipt]。Gateway 和 [AppSession]
/// 的生命周期仍由 composition root 管理。
final class OrganizationCreationDialog extends StatefulWidget {
  const OrganizationCreationDialog({
    super.key,
    required this.text,
    required this.gateway,
    required this.appSession,
    this.requestIdGenerator = secureUuidV4,
  });

  final AppStrings text;
  final OrganizationCreationGateway gateway;
  final AppSession appSession;
  final String Function() requestIdGenerator;

  @override
  State<OrganizationCreationDialog> createState() =>
      _OrganizationCreationDialogState();
}

final class _OrganizationCreationDialogState
    extends State<OrganizationCreationDialog> {
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  StreamSubscription<AppSessionSnapshot>? _sessionSubscription;

  String? _trustedAppUserId;
  String? _intentName;
  String? _requestId;
  OrganizationCreationFailureCode? _failure;
  String? _localFailure;
  var _busy = false;
  var _uncertain = false;
  var _confirmDiscard = false;
  var _sessionExpired = false;
  var _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _trustedAppUserId = _readyAppUserId(widget.appSession.current);
    _sessionExpired = _trustedAppUserId == null;
    _sessionSubscription = widget.appSession.changes.listen(_sessionChanged);
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    unawaited(_sessionSubscription?.cancel());
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<OrganizationCreationReceipt>(
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 560),
        scrollable: true,
        title: Text(
          _confirmDiscard
              ? widget.text.t('organizationCreateDiscardTitle')
              : widget.text.t('organizationCreate'),
        ),
        content: _content(context),
        actions: _actions(),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    if (_confirmDiscard) {
      return Text(widget.text.t('organizationCreateDiscardBody'));
    }

    final status = _statusMessage;
    final uncertainMessage = _uncertain
        ? widget.text.t('organizationCreateUncertain')
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.text.t('organizationCreateHelp')),
        const SizedBox(height: 12),
        Text(
          widget.text.t('organizationCreateRetryScope'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!_sessionExpired) ...[
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('organization-name'),
            controller: _nameController,
            focusNode: _nameFocusNode,
            autofocus: true,
            readOnly: _busy || _uncertain,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.text.t('organizationName'),
              errorText: _localFailure,
            ),
            onChanged: (_) {
              if (_uncertain || (_failure == null && _localFailure == null)) {
                return;
              }
              setState(() {
                _failure = null;
                _localFailure = null;
              });
            },
            onSubmitted: (_) => unawaited(_submit()),
          ),
        ],
        if (status != null) ...[
          const SizedBox(height: 16),
          Semantics(
            key: const ValueKey('organization-create-status'),
            container: true,
            liveRegion: true,
            label: uncertainMessage == null
                ? status
                : '$status $uncertainMessage',
            child: ExcludeSemantics(child: Text(status)),
          ),
        ],
        if (uncertainMessage != null) ...[
          const SizedBox(height: 12),
          Text(uncertainMessage),
        ],
      ],
    );
  }

  List<Widget> _actions() {
    if (_confirmDiscard) {
      return [
        TextButton(
          key: const ValueKey('organization-create-discard'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('organizationCreateDiscard')),
        ),
        FilledButton(
          key: const ValueKey('organization-create-keep-retry'),
          onPressed: () => setState(() => _confirmDiscard = false),
          child: Text(widget.text.t('organizationCreateKeepRetry')),
        ),
      ];
    }

    return [
      TextButton(
        key: const ValueKey('organization-create-cancel'),
        onPressed: _busy ? null : _requestClose,
        child: Text(widget.text.t('cancel')),
      ),
      if (!_sessionExpired)
        FilledButton(
          key: const ValueKey('organization-create-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(
            _uncertain
                ? widget.text.t('retry')
                : widget.text.t('organizationCreate'),
          ),
        ),
    ];
  }

  String? get _statusMessage {
    if (_busy) return widget.text.t('organizationCreating');
    if (_sessionExpired) {
      return widget.text.t('organizationCreateFailure.unauthorized');
    }
    final failure = _failure;
    if (failure == null) return null;
    return widget.text.t('organizationCreateFailure.${failure.name}');
  }

  Future<void> _submit() async {
    if (_busy || _confirmDiscard || _sessionExpired) return;
    if (!_hasTrustedSession(widget.appSession.current)) {
      _expireSession();
      return;
    }

    late final String name;
    late final String requestId;
    if (_uncertain) {
      name = _intentName!;
      requestId = _requestId!;
    } else {
      name = _nameController.text;
      final visibleName = name.replaceAll(RegExp(r'^ +| +$'), '');
      if (name.trim().isEmpty || visibleName.runes.length > 120) {
        setState(() {
          _localFailure = widget.text.t('organizationCreateNameInvalid');
          _failure = null;
        });
        _nameFocusNode.requestFocus();
        return;
      }

      // ponytail: 意图只存于当前对话框；产品要求跨重启重试时再持久化。
      if (_intentName != name) {
        _intentName = name;
        _requestId = widget.requestIdGenerator();
      }
      requestId = _requestId!;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _busy = true;
      _failure = null;
      _localFailure = null;
    });

    OrganizationCreationResult result;
    try {
      result = await widget.gateway.create(
        requestId: requestId,
        displayName: name,
      );
    } catch (_) {
      result = const OrganizationCreationRejected(
        OrganizationCreationFailureCode.invalidResponse,
      );
    }

    if (!mounted || generation != _requestGeneration) {
      return;
    }
    if (!_hasTrustedSession(widget.appSession.current)) {
      _expireSession();
      return;
    }
    switch (result) {
      case OrganizationCreationSuccess(:final receipt):
        Navigator.of(context).pop(receipt);
      case OrganizationCreationRejected(:final code):
        final uncertain = _uncertain || _isUncertain(code);
        setState(() {
          _busy = false;
          _failure = code;
          _uncertain = uncertain;
        });
        if (!uncertain) _nameFocusNode.requestFocus();
    }
  }

  void _sessionChanged(AppSessionSnapshot snapshot) {
    if (!_hasTrustedSession(snapshot)) _expireSession();
  }

  void _expireSession() {
    if (_sessionExpired || !mounted) return;
    _requestGeneration += 1;
    _nameController.clear();
    _intentName = null;
    _requestId = null;
    setState(() {
      _sessionExpired = true;
      _busy = false;
      _uncertain = false;
      _confirmDiscard = false;
      _failure = null;
      _localFailure = null;
    });
  }

  void _requestClose() {
    if (_busy) return;
    if (_confirmDiscard) {
      setState(() => _confirmDiscard = false);
      return;
    }
    if (_uncertain) {
      setState(() => _confirmDiscard = true);
      return;
    }
    Navigator.of(context).pop();
  }

  bool _hasTrustedSession(AppSessionSnapshot snapshot) =>
      !_sessionExpired &&
      snapshot.stage == AppSessionStage.ready &&
      snapshot.context?.appUserId == _trustedAppUserId;

  static String? _readyAppUserId(AppSessionSnapshot snapshot) =>
      snapshot.stage == AppSessionStage.ready
      ? snapshot.context?.appUserId
      : null;

  static bool _isUncertain(OrganizationCreationFailureCode code) =>
      switch (code) {
        OrganizationCreationFailureCode.conflict ||
        OrganizationCreationFailureCode.serviceUnavailable ||
        OrganizationCreationFailureCode.networkUnavailable ||
        OrganizationCreationFailureCode.invalidResponse => true,
        _ => false,
      };
}
