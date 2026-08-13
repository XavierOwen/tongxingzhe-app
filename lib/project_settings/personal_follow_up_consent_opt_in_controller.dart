import 'package:flutter/foundation.dart';

import 'personal_follow_up_consent_opt_in.dart';

enum PersonalFollowUpConsentOptInStage { loading, ready, saving, failed }

final class PersonalFollowUpConsentOptInControllerState {
  const PersonalFollowUpConsentOptInControllerState({
    required this.stage,
    required this.value,
    required this.failureCode,
  });

  const PersonalFollowUpConsentOptInControllerState.loading()
    : stage = PersonalFollowUpConsentOptInStage.loading,
      value = null,
      failureCode = null;

  final PersonalFollowUpConsentOptInStage stage;
  final PersonalFollowUpConsentOptInState? value;
  final PersonalFollowUpConsentOptInFailureCode? failureCode;

  bool get isBusy =>
      stage == PersonalFollowUpConsentOptInStage.loading ||
      stage == PersonalFollowUpConsentOptInStage.saving;

  bool get isNeverConfigured => value != null && value!.configuration == null;

  bool get isEnabled => value?.configuration?.enabled == true;

  PersonalFollowUpConsentOptInControllerState copyWith({
    PersonalFollowUpConsentOptInStage? stage,
    PersonalFollowUpConsentOptInState? value,
    bool clearValue = false,
    PersonalFollowUpConsentOptInFailureCode? failureCode,
    bool clearFailure = false,
  }) => PersonalFollowUpConsentOptInControllerState(
    stage: stage ?? this.stage,
    value: clearValue ? null : value ?? this.value,
    failureCode: clearFailure ? null : failureCode ?? this.failureCode,
  );
}

final class PersonalFollowUpConsentOptInController extends ChangeNotifier {
  factory PersonalFollowUpConsentOptInController({
    required PersonalFollowUpConsentOptInGateway gateway,
    required ConsentOptInRequestIdGenerator requestIdGenerator,
    required String scopeKey,
  }) => PersonalFollowUpConsentOptInController._(
    gateway,
    requestIdGenerator,
    scopeKey,
  );

  PersonalFollowUpConsentOptInController._(
    this._gateway,
    this._requestIdGenerator,
    this._scopeKey,
  );

  final PersonalFollowUpConsentOptInGateway _gateway;
  final ConsentOptInRequestIdGenerator _requestIdGenerator;
  String _scopeKey;
  PersonalFollowUpConsentOptInControllerState _state =
      const PersonalFollowUpConsentOptInControllerState.loading();
  _PendingMutation? _pendingMutation;
  int _generation = 0;
  bool _disposed = false;

  PersonalFollowUpConsentOptInControllerState get state => _state;

  String get scopeKey => _scopeKey;

  Future<void> load() async {
    final generation = ++_generation;
    _pendingMutation = null;
    _publish(
      _state.copyWith(
        stage: PersonalFollowUpConsentOptInStage.loading,
        clearValue: true,
        clearFailure: true,
      ),
    );
    final result = await _gateway.load();
    _applyLoadResult(result, generation);
  }

  Future<void> changeScope(String scopeKey) async {
    if (_disposed || scopeKey == _scopeKey) {
      if (!_disposed && scopeKey == _scopeKey) await load();
      return;
    }
    _scopeKey = scopeKey;
    final generation = ++_generation;
    _pendingMutation = null;
    _publish(const PersonalFollowUpConsentOptInControllerState.loading());
    final result = await _gateway.load();
    _applyLoadResult(result, generation);
  }

  Future<void> setEnabled(bool enabled) async {
    if (_disposed || _state.stage == PersonalFollowUpConsentOptInStage.saving) {
      return;
    }
    final current = _state.value;
    if (current == null) return;
    final currentEnabled = current.configuration?.enabled == true;
    if (_pendingMutation == null && enabled == currentEnabled) return;

    final pending = _pendingMutation;
    final mutation = pending != null && pending.enabled == enabled
        ? pending
        : _PendingMutation(
            expectedVersion: current.configuration?.versionNumber ?? 0,
            enabled: enabled,
            requestId: _requestIdGenerator.next(),
          );
    _pendingMutation = mutation;
    await _executeMutation(mutation);
  }

  Future<void> retry() async {
    if (_disposed || _state.stage == PersonalFollowUpConsentOptInStage.saving) {
      return;
    }
    final pending = _pendingMutation;
    if (pending != null) {
      await _executeMutation(pending);
      return;
    }
    await load();
  }

  Future<void> _executeMutation(_PendingMutation mutation) async {
    if (_disposed || _state.stage == PersonalFollowUpConsentOptInStage.saving) {
      return;
    }
    final generation = ++_generation;
    _publish(
      _state.copyWith(
        stage: PersonalFollowUpConsentOptInStage.saving,
        clearFailure: true,
      ),
    );
    final result = await _gateway.configure(
      expectedVersion: mutation.expectedVersion,
      enabled: mutation.enabled,
      requestId: mutation.requestId,
    );
    if (!_isCurrent(generation)) return;

    switch (result) {
      case PersonalFollowUpConsentOptInSuccess(:final value):
        if (!_configurationMatchesScope(value)) {
          _pendingMutation = null;
          _publish(
            _state.copyWith(
              stage: PersonalFollowUpConsentOptInStage.failed,
              failureCode:
                  PersonalFollowUpConsentOptInFailureCode.invalidResponse,
            ),
          );
          return;
        }
        _pendingMutation = null;
        _publish(
          PersonalFollowUpConsentOptInControllerState(
            stage: PersonalFollowUpConsentOptInStage.ready,
            value: _stateFromConfiguration(value),
            failureCode: null,
          ),
        );
      case PersonalFollowUpConsentOptInRejected(:final code)
          when code == PersonalFollowUpConsentOptInFailureCode.conflict:
        _pendingMutation = null;
        await _reloadAfterConflict(generation);
      case PersonalFollowUpConsentOptInRejected(:final code):
        _publish(
          _state.copyWith(
            stage: PersonalFollowUpConsentOptInStage.failed,
            failureCode: code,
          ),
        );
    }
  }

  Future<void> _reloadAfterConflict(int generation) async {
    final result = await _gateway.load();
    if (!_isCurrent(generation)) return;
    switch (result) {
      case PersonalFollowUpConsentOptInSuccess(:final value):
        if (!_stateMatchesScope(value)) {
          _publish(
            _state.copyWith(
              stage: PersonalFollowUpConsentOptInStage.failed,
              failureCode:
                  PersonalFollowUpConsentOptInFailureCode.invalidResponse,
            ),
          );
          return;
        }
        _publish(
          PersonalFollowUpConsentOptInControllerState(
            stage: PersonalFollowUpConsentOptInStage.ready,
            value: value,
            failureCode: PersonalFollowUpConsentOptInFailureCode.conflict,
          ),
        );
      case PersonalFollowUpConsentOptInRejected(:final code):
        _publish(
          _state.copyWith(
            stage: PersonalFollowUpConsentOptInStage.failed,
            failureCode: code,
          ),
        );
    }
  }

  void _applyLoadResult(
    PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
    result,
    int generation,
  ) {
    if (!_isCurrent(generation)) return;
    switch (result) {
      case PersonalFollowUpConsentOptInSuccess(:final value):
        if (!_stateMatchesScope(value)) {
          _publish(
            const PersonalFollowUpConsentOptInControllerState(
              stage: PersonalFollowUpConsentOptInStage.failed,
              value: null,
              failureCode:
                  PersonalFollowUpConsentOptInFailureCode.invalidResponse,
            ),
          );
          return;
        }
        _publish(
          PersonalFollowUpConsentOptInControllerState(
            stage: PersonalFollowUpConsentOptInStage.ready,
            value: value,
            failureCode: null,
          ),
        );
      case PersonalFollowUpConsentOptInRejected(:final code):
        _publish(
          PersonalFollowUpConsentOptInControllerState(
            stage: PersonalFollowUpConsentOptInStage.failed,
            value: null,
            failureCode: code,
          ),
        );
    }
  }

  PersonalFollowUpConsentOptInState _stateFromConfiguration(
    PersonalFollowUpConsentOptInConfiguration configuration,
  ) => PersonalFollowUpConsentOptInState(
    stateContractId: personalFollowUpConsentOptInStateContract,
    metricId: configuration.metricId,
    projectId: configuration.projectId,
    status: configuration.enabled
        ? PersonalFollowUpConsentOptInStatus.enabled
        : PersonalFollowUpConsentOptInStatus.notEnabled,
    configuration: configuration,
  );

  bool _stateMatchesScope(PersonalFollowUpConsentOptInState value) =>
      value.projectId.toLowerCase() == _scopeKey.toLowerCase() &&
      (value.configuration == null ||
          _configurationMatchesScope(value.configuration!));

  bool _configurationMatchesScope(
    PersonalFollowUpConsentOptInConfiguration value,
  ) => value.projectId.toLowerCase() == _scopeKey.toLowerCase();

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _publish(PersonalFollowUpConsentOptInControllerState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _PendingMutation {
  const _PendingMutation({
    required this.expectedVersion,
    required this.enabled,
    required this.requestId,
  });

  final int expectedVersion;
  final bool enabled;
  final String requestId;
}
