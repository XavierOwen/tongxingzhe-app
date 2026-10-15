import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_session/app_session.dart';
import '../../app_session/session_context_gateway.dart';
import '../../identity/identity_session.dart';
import '../../targets/personal_target_merge_projection.dart';

typedef _ReadScope = ({
  String subject,
  String actorId,
  String workspaceId,
  String projectId,
});

final class PersonalTargetMergeProjectionReadController extends ChangeNotifier {
  PersonalTargetMergeProjectionReadController({
    required IdentitySession identitySession,
    required AppSession appSession,
    required PersonalTargetMergeProjectionGateway gateway,
  }) : _identitySession = identitySession,
       _appSession = appSession,
       // ignore: prefer_initializing_formals
       _gateway = gateway {
    _identitySubscription = identitySession.changes.listen(
      _identityChanged,
      onError: (Object _, StackTrace _) => _streamUnavailable(),
      onDone: _streamUnavailable,
    );
    _appSessionSubscription = appSession.changes.listen(
      _appSessionChanged,
      onError: (Object _, StackTrace _) => _streamUnavailable(),
      onDone: _streamUnavailable,
    );
  }

  final IdentitySession _identitySession;
  final AppSession _appSession;
  final PersonalTargetMergeProjectionGateway _gateway;
  late final StreamSubscription<IdentitySnapshot> _identitySubscription;
  late final StreamSubscription<AppSessionSnapshot> _appSessionSubscription;
  _ReadScope? _scope;
  String? _selectedGenerationId;
  PersonalTargetMergeProjection? _projection;
  PersonalTargetMergeProjectionFailure? _failure;
  var _loading = false;
  var _generation = 0;
  var _streamsAvailable = true;
  var _disposed = false;

  String? get selectedGenerationId => _selectedGenerationId;
  bool get loading => _loading;
  PersonalTargetMergeProjection? get projection => _projection;
  PersonalTargetMergeProjectionFailure? get failure => _failure;

  Future<void> read(String generationId) async {
    if (_disposed) return;
    final generation = ++_generation;
    _selectedGenerationId = generationId;
    _projection = null;
    _failure = null;
    _loading = false;
    final scope = _eligibleScope(_appSession.current, _identitySession.current);
    _scope = scope;
    if (!_streamsAvailable || scope == null) {
      _failure = _identitySession.current.stage == IdentityStage.signedIn
          ? PersonalTargetMergeProjectionFailure.forbidden
          : PersonalTargetMergeProjectionFailure.unauthenticated;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    if (!_isCurrent(generation, scope)) return;

    PersonalTargetMergeProjectionResult result;
    try {
      result = await _gateway.read(
        expectedSubject: scope.subject,
        workspaceId: scope.workspaceId,
        projectId: scope.projectId,
        generationId: generationId,
        requestIsCurrent: () => _isCurrent(generation, scope),
      );
    } catch (_) {
      result = const PersonalTargetMergeProjectionRejected(
        PersonalTargetMergeProjectionFailure.serviceUnavailable,
      );
    }
    if (!_isCurrent(generation, scope)) {
      if (!_disposed && generation == _generation) _invalidate();
      return;
    }
    _loading = false;
    switch (result) {
      case PersonalTargetMergeProjectionReady(:final projection):
        _projection = projection;
      case PersonalTargetMergeProjectionRejected(:final failure):
        _failure = failure;
    }
    notifyListeners();
  }

  _ReadScope? _eligibleScope(
    AppSessionSnapshot snapshot,
    IdentitySnapshot identity,
  ) {
    final subject = identity.principal?.externalSubject;
    final context = snapshot.context;
    if (identity.stage != IdentityStage.signedIn ||
        subject == null ||
        snapshot.stage != AppSessionStage.ready ||
        snapshot.fromOfflineCache ||
        snapshot.identity?.stage != IdentityStage.signedIn ||
        snapshot.identity?.principal?.externalSubject != subject ||
        context == null ||
        context.workspace.kind != WorkspaceKind.personal ||
        !context.capabilities.contains('view_assigned_target_pii') ||
        !context.capabilities.contains('manage_assigned_target_merges')) {
      return null;
    }
    return (
      subject: subject,
      actorId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
    );
  }

  bool _isCurrent(int generation, _ReadScope scope) =>
      !_disposed &&
      _streamsAvailable &&
      generation == _generation &&
      _scope == scope &&
      _eligibleScope(_appSession.current, _identitySession.current) == scope;

  void _identityChanged(IdentitySnapshot identity) {
    if (_scope != null &&
        _eligibleScope(_appSession.current, identity) != _scope) {
      _invalidate();
    }
  }

  void _appSessionChanged(AppSessionSnapshot snapshot) {
    if (_scope != null &&
        _eligibleScope(snapshot, _identitySession.current) != _scope) {
      _invalidate();
    }
  }

  void _streamUnavailable() {
    _streamsAvailable = false;
    _invalidate();
  }

  void _invalidate() {
    if (_disposed) return;
    _generation++;
    _scope = null;
    _selectedGenerationId = null;
    _loading = false;
    _projection = null;
    _failure = PersonalTargetMergeProjectionFailure.requestInvalidated;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _scope = null;
    _selectedGenerationId = null;
    _projection = null;
    _failure = null;
    _loading = false;
    unawaited(_identitySubscription.cancel());
    unawaited(_appSessionSubscription.cancel());
    super.dispose();
  }
}
