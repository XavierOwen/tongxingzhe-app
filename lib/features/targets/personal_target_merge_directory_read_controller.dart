import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app_session/app_session.dart';
import '../../app_session/session_context_gateway.dart';
import '../../identity/identity_session.dart';
import '../../targets/personal_target_merge_directory.dart';

typedef _ReadScope = ({
  String subject,
  String actorId,
  String workspaceId,
  String projectId,
});

final class PersonalTargetMergeDirectoryReadController extends ChangeNotifier {
  PersonalTargetMergeDirectoryReadController({
    required IdentitySession identitySession,
    required AppSession appSession,
    required PersonalTargetMergeDirectoryGateway gateway,
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
  final PersonalTargetMergeDirectoryGateway _gateway;
  late final StreamSubscription<IdentitySnapshot> _identitySubscription;
  late final StreamSubscription<AppSessionSnapshot> _appSessionSubscription;
  _ReadScope? _scope;
  String? _selectedGenerationId;
  PersonalTargetMergeDirectory? _directory;
  PersonalTargetMergeDirectoryFailure? _failure;
  var _loading = false;
  var _generation = 0;
  var _streamsAvailable = true;
  var _disposed = false;

  String? get selectedGenerationId => _selectedGenerationId;
  bool get loading => _loading;
  PersonalTargetMergeDirectory? get directory => _directory;
  PersonalTargetMergeDirectoryFailure? get failure => _failure;

  Future<void> read({String? afterGenerationId}) async {
    if (_disposed) return;
    final generation = ++_generation;
    _selectedGenerationId = null;
    _directory = null;
    _failure = null;
    _loading = false;
    final scope = _eligibleScope(_appSession.current, _identitySession.current);
    _scope = scope;
    if (!_streamsAvailable || scope == null) {
      _failure = _identitySession.current.stage == IdentityStage.signedIn
          ? PersonalTargetMergeDirectoryFailure.forbidden
          : PersonalTargetMergeDirectoryFailure.unauthenticated;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    if (!_isCurrent(generation, scope)) return;

    PersonalTargetMergeDirectoryResult result;
    try {
      result = await _gateway.read(
        expectedSubject: scope.subject,
        workspaceId: scope.workspaceId,
        projectId: scope.projectId,
        afterGenerationId: afterGenerationId,
        requestIsCurrent: () => _isCurrent(generation, scope),
      );
    } catch (_) {
      result = const PersonalTargetMergeDirectoryRejected(
        PersonalTargetMergeDirectoryFailure.serviceUnavailable,
      );
    }
    if (!_isCurrent(generation, scope)) {
      if (!_disposed && generation == _generation) _invalidate();
      return;
    }
    _loading = false;
    switch (result) {
      case PersonalTargetMergeDirectoryReady(:final directory):
        _directory = directory;
      case PersonalTargetMergeDirectoryRejected(:final failure):
        _failure = failure;
    }
    notifyListeners();
  }

  bool selectGeneration(String? id) {
    if (_disposed) return false;
    final scope = _scope;
    if (scope == null || !_isCurrent(_generation, scope)) {
      _invalidate();
      return false;
    }
    if (id == null) {
      _selectedGenerationId = null;
      notifyListeners();
      return true;
    }
    final page = _directory;
    if (page == null || _loading) return false;
    for (final item in page.items) {
      if (item.generationId.toLowerCase() == id.toLowerCase()) {
        _selectedGenerationId = item.generationId;
        notifyListeners();
        return true;
      }
    }
    return false;
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
    _directory = null;
    _failure = PersonalTargetMergeDirectoryFailure.requestInvalidated;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _scope = null;
    _selectedGenerationId = null;
    _directory = null;
    _failure = null;
    _loading = false;
    unawaited(_identitySubscription.cancel());
    unawaited(_appSessionSubscription.cancel());
    super.dispose();
  }
}
