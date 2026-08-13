import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/project_settings/personal_follow_up_consent_opt_in.dart';
import 'package:tongxingzhe_app/project_settings/personal_follow_up_consent_opt_in_controller.dart';

void main() {
  test(
    'load exposes loading, ready, and failed states without caching',
    () async {
      final gateway = _FakeGateway();
      final controller = _controller(gateway);
      addTearDown(controller.dispose);

      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.loading);

      final load = controller.load();
      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.loading);
      gateway.completeLoad(
        PersonalFollowUpConsentOptInSuccess(_state(configuration: null)),
      );
      await load;
      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.ready);
      expect(controller.state.value!.configuration, isNull);

      gateway.nextLoadResult = const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      );
      await controller.load();
      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.failed);
      expect(
        controller.state.failureCode,
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      );
    },
  );

  test(
    'saving ignores a second tap and retries the exact intent and request id',
    () async {
      final gateway = _FakeGateway();
      final ids = _Ids();
      final controller = _controller(gateway, ids: ids);
      addTearDown(controller.dispose);
      await _load(
        controller,
        gateway,
        _state(configuration: _configuration(false)),
      );

      final firstSave = controller.setEnabled(true);
      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.saving);
      await controller.setEnabled(true);
      expect(gateway.configureCalls, hasLength(1));
      gateway.completeConfigure(
        const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
        ),
      );
      await firstSave;
      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.failed);
      expect(
        controller.state.failureCode,
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      );

      final retry = controller.retry();
      expect(gateway.configureCalls, hasLength(2));
      expect(gateway.configureCalls[0], gateway.configureCalls[1]);
      gateway.completeConfigure(
        PersonalFollowUpConsentOptInSuccess(_configuration(true)),
      );
      await retry;
      expect(controller.state.stage, PersonalFollowUpConsentOptInStage.ready);
      expect(controller.state.value!.configuration!.enabled, isTrue);
      expect(ids.generated, ['request-1']);
    },
  );

  test('a new choice gets a new request id after an uncertain save', () async {
    final gateway = _FakeGateway();
    final ids = _Ids();
    final controller = _controller(gateway, ids: ids);
    addTearDown(controller.dispose);
    await _load(
      controller,
      gateway,
      _state(configuration: _configuration(false)),
    );

    final firstSave = controller.setEnabled(true);
    gateway.completeConfigure(
      const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      ),
    );
    await firstSave;

    final secondSave = controller.setEnabled(false);
    expect(gateway.configureCalls, hasLength(2));
    expect(gateway.configureCalls[0].requestId, 'request-1');
    expect(gateway.configureCalls[1].requestId, 'request-2');
    gateway.completeConfigure(
      PersonalFollowUpConsentOptInSuccess(_configuration(false, version: 2)),
    );
    await secondSave;
    expect(ids.generated, ['request-1', 'request-2']);
  });

  test(
    '409 reloads the latest state but requires an explicit new choice',
    () async {
      final gateway = _FakeGateway();
      final ids = _Ids();
      final controller = _controller(gateway, ids: ids);
      addTearDown(controller.dispose);
      await _load(
        controller,
        gateway,
        _state(configuration: _configuration(false)),
      );

      final save = controller.setEnabled(true);
      gateway.completeConfigure(
        const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.conflict,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      gateway.completeLoad(
        PersonalFollowUpConsentOptInSuccess(
          _state(configuration: _configuration(true, version: 2)),
        ),
      );
      await save;

      expect(gateway.loadCalls, 2);
      expect(gateway.configureCalls, hasLength(1));
      expect(controller.state.value!.configuration!.versionNumber, 2);
      expect(
        controller.state.failureCode,
        PersonalFollowUpConsentOptInFailureCode.conflict,
      );

      final explicitChoice = controller.setEnabled(false);
      expect(gateway.configureCalls, hasLength(2));
      expect(gateway.configureCalls.last.expectedVersion, 2);
      expect(gateway.configureCalls.last.requestId, 'request-2');
      gateway.completeConfigure(
        PersonalFollowUpConsentOptInSuccess(_configuration(false, version: 3)),
      );
      await explicitChoice;
    },
  );

  test('scope changes invalidate stale responses', () async {
    final gateway = _FakeGateway();
    final controller = _controller(gateway, scopeKey: 'project-a');
    addTearDown(controller.dispose);

    final oldLoad = controller.load();
    await Future<void>.delayed(Duration.zero);
    final newLoad = controller.changeScope('project-b');
    expect(controller.scopeKey, 'project-b');
    gateway.completeLoadAt(
      PersonalFollowUpConsentOptInSuccess(
        _state(
          configuration: _configuration(true, projectId: 'project-b'),
          projectId: 'project-b',
        ),
      ),
      1,
    );
    await newLoad;
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: _configuration(false, projectId: 'project-a')),
      ),
    );
    await oldLoad;

    expect(controller.state.value!.projectId, 'project-b');
    expect(controller.state.value!.configuration!.enabled, isTrue);
  });

  test('dispose prevents a late load from publishing state', () async {
    final gateway = _FakeGateway();
    final controller = _controller(gateway);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final load = controller.load();
    controller.dispose();
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(_state(configuration: null)),
    );

    await expectLater(load, completes);
    expect(notifications, 1);
  });

  test('a response for another project fails closed', () async {
    final gateway = _FakeGateway();
    final controller = _controller(gateway, scopeKey: 'project-a');
    addTearDown(controller.dispose);

    final load = controller.load();
    gateway.completeLoad(
      PersonalFollowUpConsentOptInSuccess(
        _state(configuration: null, projectId: 'project-b'),
      ),
    );
    await load;

    expect(controller.state.stage, PersonalFollowUpConsentOptInStage.failed);
    expect(controller.state.value, isNull);
    expect(
      controller.state.failureCode,
      PersonalFollowUpConsentOptInFailureCode.invalidResponse,
    );
  });
}

PersonalFollowUpConsentOptInController _controller(
  _FakeGateway gateway, {
  _Ids? ids,
  String scopeKey = 'project-a',
}) => PersonalFollowUpConsentOptInController(
  gateway: gateway,
  requestIdGenerator: ids ?? _Ids(),
  scopeKey: scopeKey,
);

Future<void> _load(
  PersonalFollowUpConsentOptInController controller,
  _FakeGateway gateway,
  PersonalFollowUpConsentOptInState state,
) async {
  final load = controller.load();
  gateway.completeLoad(PersonalFollowUpConsentOptInSuccess(state));
  await load;
}

final class _Ids implements ConsentOptInRequestIdGenerator {
  final generated = <String>[];

  @override
  String next() {
    final id = 'request-${generated.length + 1}';
    generated.add(id);
    return id;
  }
}

final class _ConfigureCall {
  const _ConfigureCall({
    required this.expectedVersion,
    required this.enabled,
    required this.requestId,
  });

  final int expectedVersion;
  final bool enabled;
  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is _ConfigureCall &&
      other.expectedVersion == expectedVersion &&
      other.enabled == enabled &&
      other.requestId == requestId;

  @override
  int get hashCode => Object.hash(expectedVersion, enabled, requestId);
}

final class _FakeGateway implements PersonalFollowUpConsentOptInGateway {
  final _loadResults =
      <
        Completer<
          PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
        >
      >[];
  final _configureResults =
      <
        Completer<
          PersonalFollowUpConsentOptInResult<
            PersonalFollowUpConsentOptInConfiguration
          >
        >
      >[];
  final configureCalls = <_ConfigureCall>[];
  int loadCalls = 0;
  PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>?
  nextLoadResult;

  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  _pendingLoad() {
    final completer =
        Completer<
          PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
        >();
    _loadResults.add(completer);
    return completer.future;
  }

  @override
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load() {
    loadCalls++;
    final result = nextLoadResult;
    nextLoadResult = null;
    if (result != null) return Future.value(result);
    return _pendingLoad();
  }

  @override
  Future<
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
  >
  configure({
    required int expectedVersion,
    required bool enabled,
    required String requestId,
  }) {
    configureCalls.add(
      _ConfigureCall(
        expectedVersion: expectedVersion,
        enabled: enabled,
        requestId: requestId,
      ),
    );
    final completer =
        Completer<
          PersonalFollowUpConsentOptInResult<
            PersonalFollowUpConsentOptInConfiguration
          >
        >();
    _configureResults.add(completer);
    return completer.future;
  }

  void completeLoad(
    PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
    result,
  ) {
    final index = _loadResults.indexWhere(
      (completer) => !completer.isCompleted,
    );
    completeLoadAt(result, index);
  }

  void completeLoadAt(
    PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>
    result,
    int index,
  ) {
    final completer = _loadResults[index];
    completer.complete(result);
  }

  void completeConfigure(
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
    result,
  ) {
    final completer = _configureResults.removeAt(0);
    completer.complete(result);
  }

  @override
  Future<void> close() async {}
}

PersonalFollowUpConsentOptInState _state({
  required PersonalFollowUpConsentOptInConfiguration? configuration,
  String projectId = 'project-a',
}) => PersonalFollowUpConsentOptInState(
  stateContractId: personalFollowUpConsentOptInStateContract,
  metricId: personalFollowUpConsentOptInMetric,
  projectId: projectId,
  status: configuration?.enabled == true
      ? PersonalFollowUpConsentOptInStatus.enabled
      : PersonalFollowUpConsentOptInStatus.notEnabled,
  configuration: configuration,
);

PersonalFollowUpConsentOptInConfiguration _configuration(
  bool enabled, {
  int version = 1,
  String projectId = 'project-a',
}) => PersonalFollowUpConsentOptInConfiguration(
  configurationContractId: personalFollowUpConsentOptInConfigurationContract,
  metricId: personalFollowUpConsentOptInMetric,
  projectId: projectId,
  versionNumber: version,
  expectedVersion: version - 1,
  enabled: enabled,
  requestId: 'server-request-$version',
  recordedAtUtc: DateTime.utc(2026, 8, 13),
);
