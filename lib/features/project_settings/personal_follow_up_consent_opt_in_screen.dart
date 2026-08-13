import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../project_settings/personal_follow_up_consent_opt_in.dart';
import '../../project_settings/personal_follow_up_consent_opt_in_controller.dart';

final class PersonalFollowUpConsentOptInScreen extends StatefulWidget {
  const PersonalFollowUpConsentOptInScreen({
    super.key,
    required this.text,
    required this.projectId,
    required this.gateway,
    required this.requestIdGenerator,
  });

  final AppStrings text;
  final String projectId;
  final PersonalFollowUpConsentOptInGateway gateway;
  final ConsentOptInRequestIdGenerator requestIdGenerator;

  @override
  State<PersonalFollowUpConsentOptInScreen> createState() =>
      _PersonalFollowUpConsentOptInScreenState();
}

final class _PersonalFollowUpConsentOptInScreenState
    extends State<PersonalFollowUpConsentOptInScreen> {
  late final PersonalFollowUpConsentOptInController _controller;
  var _saved = false;
  PersonalFollowUpConsentOptInStage? _previousStage;

  @override
  void initState() {
    super.initState();
    _controller = PersonalFollowUpConsentOptInController(
      gateway: widget.gateway,
      requestIdGenerator: widget.requestIdGenerator,
      scopeKey: widget.projectId,
    )..addListener(_stateChanged);
    unawaited(_controller.load());
  }

  @override
  void didUpdateWidget(PersonalFollowUpConsentOptInScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId == widget.projectId) {
      return;
    }
    _saved = false;
    _previousStage = null;
    unawaited(_controller.changeScope(widget.projectId));
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_stateChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        unawaited(Navigator.maybePop(context));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.text.t('projectSettings')),
          leading: IconButton(
            key: const ValueKey('consent-opt-in-close'),
            tooltip: widget.text.t('cancel'),
            onPressed: () => unawaited(Navigator.maybePop(context)),
            icon: const Icon(Icons.close),
          ),
        ),
        body: _body(context),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final state = _controller.state;
    if (state.stage == PersonalFollowUpConsentOptInStage.loading) {
      return _loadingView();
    }
    if (state.value == null) {
      return _failureView(state.failureCode);
    }
    return _settingsView(context, state);
  }

  Widget _loadingView() => Center(
    child: Semantics(
      key: const ValueKey('consent-opt-in-loading'),
      container: true,
      liveRegion: true,
      label: widget.text.t('consentOptInLoading'),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(widget.text.t('consentOptInLoading')),
          ],
        ),
      ),
    ),
  );

  Widget _failureView(PersonalFollowUpConsentOptInFailureCode? code) {
    final message = _failureMessage(code);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          key: const ValueKey('consent-opt-in-error'),
          container: true,
          liveRegion: true,
          label: message,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('consent-opt-in-retry'),
                onPressed: _controller.state.isBusy
                    ? null
                    : () => unawaited(_controller.retry()),
                icon: const Icon(Icons.refresh),
                label: Text(widget.text.t('consentOptInRetry')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsView(
    BuildContext context,
    PersonalFollowUpConsentOptInControllerState state,
  ) {
    final status = state.isNeverConfigured
        ? widget.text.t('consentOptInNeverConfigured')
        : state.isEnabled
        ? widget.text.t('consentOptInEnabled')
        : widget.text.t('consentOptInDisabled');
    final statusText = widget.text
        .t('consentOptInCurrentStatus')
        .replaceFirst('{status}', status);
    final hasFailure = state.failureCode != null;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    widget.text.t('consentOptInTitle'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                Text(widget.text.t('consentOptInExplanation')),
                const SizedBox(height: 12),
                Text(
                  widget.text.t('consentOptInHistoryNote'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                Semantics(
                  container: true,
                  liveRegion: hasFailure,
                  label: statusText,
                  child: Text(statusText),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  key: const ValueKey('consent-opt-in-toggle'),
                  contentPadding: EdgeInsets.zero,
                  value: state.isEnabled,
                  onChanged: state.isBusy
                      ? null
                      : (enabled) => unawaited(_controller.setEnabled(enabled)),
                  title: Text(
                    state.isEnabled
                        ? widget.text.t('consentOptInDisableAction')
                        : widget.text.t('consentOptInEnableAction'),
                  ),
                  subtitle: Text(status),
                ),
                if (state.stage == PersonalFollowUpConsentOptInStage.saving)
                  _liveMessage(widget.text.t('consentOptInSaving')),
                if (_saved) _liveMessage(widget.text.t('consentOptInSaved')),
                if (hasFailure) ...[
                  const SizedBox(height: 8),
                  _liveMessage(_failureMessage(state.failureCode)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const ValueKey('consent-opt-in-retry'),
                      onPressed: state.isBusy
                          ? null
                          : () => unawaited(_controller.retry()),
                      icon: const Icon(Icons.refresh),
                      label: Text(widget.text.t('consentOptInRetry')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _liveMessage(String message) => Semantics(
    key: ValueKey('consent-opt-in-message-$message'),
    liveRegion: true,
    container: true,
    label: message,
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(message),
    ),
  );

  String _failureMessage(PersonalFollowUpConsentOptInFailureCode? code) {
    return switch (code) {
      PersonalFollowUpConsentOptInFailureCode.unauthorized => widget.text.t(
        'consentOptInUnauthorized',
      ),
      PersonalFollowUpConsentOptInFailureCode.invalidRequest => widget.text.t(
        'consentOptInInvalidRequest',
      ),
      PersonalFollowUpConsentOptInFailureCode.forbidden => widget.text.t(
        'consentOptInForbidden',
      ),
      PersonalFollowUpConsentOptInFailureCode.networkUnavailable =>
        widget.text.t('consentOptInNetworkUnavailable'),
      PersonalFollowUpConsentOptInFailureCode.invalidResponse ||
      PersonalFollowUpConsentOptInFailureCode.serverRejected => widget.text.t(
        'consentOptInInvalidResponse',
      ),
      PersonalFollowUpConsentOptInFailureCode.serviceUnavailable =>
        widget.text.t('consentOptInServiceUnavailable'),
      PersonalFollowUpConsentOptInFailureCode.notConfigured => widget.text.t(
        'consentOptInNotConfigured',
      ),
      PersonalFollowUpConsentOptInFailureCode.conflict => widget.text.t(
        'consentOptInConflict',
      ),
      null => widget.text.t('consentOptInInvalidResponse'),
    };
  }

  void _stateChanged() {
    if (!mounted) return;
    final stage = _controller.state.stage;
    if (stage == PersonalFollowUpConsentOptInStage.saving) {
      _saved = false;
    } else if (stage == PersonalFollowUpConsentOptInStage.ready &&
        _previousStage == PersonalFollowUpConsentOptInStage.saving &&
        _controller.state.failureCode == null) {
      _saved = true;
    }
    _previousStage = stage;
    setState(() {});
  }
}
