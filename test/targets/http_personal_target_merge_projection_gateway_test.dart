import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/http_personal_target_merge_projection_gateway.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_projection.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

const _subject = ' owner ';
const _workspaceId = '7ea00000-0000-4000-8000-000000000001';
const _projectId = '7ea00000-0000-4000-8000-000000000002';
const _generationId = '7ea00000-0000-4000-8000-000000000003';
const _firstId = '7ea00000-0000-4000-8000-000000000011';
const _secondId = '7ea00000-0000-4000-8000-000000000012';
const _partnerId = '7ea00000-0000-4000-8000-000000000013';
const _oldGenerationId = '7ea00000-0000-4000-8000-000000000099';
const _firstDue = '2027-10-15T12:34:56.123455Z';
const _secondDue = '2027-10-15T12:34:56.123456Z';
typedef _Document = Map<String, Object?>;

void main() {
  test(
    'uses the dedicated GET without subject, workspace, query or body',
    () async {
      final identity = _Identity();
      final gateway = _gateway(
        identity,
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://backend.example.test/v1/projects/$_projectId/promotion-target-merges/$_generationId',
          );
          expect(request.url.hasQuery, isFalse);
          expect(request.body, isEmpty);
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          expect(request.headers['accept'], 'application/json');
          expect(request.headers.containsKey('content-type'), isFalse);
          return _response(_wire());
        }),
      );
      final projection = _ready(await _read(gateway));
      expect(projection.generationId, _generationId);
      expect(projection.workspaceId, _workspaceId);
      expect(projection.projectId, _projectId);
      expect(projection.retainedTargetId, _firstId);
      expect(projection.displayNameSourceTargetId, _secondId);
      expect(projection.phoneSourceTargetId, _secondId);
      expect(projection.emailSourceTargetId, _firstId);
      expect(projection.displayName, ' Synthetic source B ');
      expect(projection.phone, isNull);
      expect(projection.email, isNull);
      expect(projection.reviewDueAtUtc, DateTime.parse(_firstDue));
      expect(projection.reviewDueAtUtc.microsecond, 455);
      expect(identity.forceRefresh, [false]);
    },
  );

  for (final type in ['person', 'institution']) {
    test(
      'preserves rich $type source facts, offsets, NULL and old binding',
      () async {
        final projection = _ready(
          await _read(
            _gateway(
              _Identity(),
              MockClient((_) async => _response(_wire(type))),
            ),
          ),
        );
        expect(projection.targetType.storageValue, type);
        expect(projection.sources, hasLength(2));
        final first = projection.sources.first;
        final second = projection.sources.last;
        expect(first.profile.targetId, _firstId);
        expect(
          first.profile.createdAtUtc,
          DateTime.utc(2026, 10, 15, 12, 34, 56, 123, 456),
        );
        expect(first.profile.phone, ' +1 312 555 0123 ');
        expect(first.projectRelationship!.stage, 0);
        expect(second.projectRelationship!.stage, 3);
        expect(
          first.projectRelationship!.updatedAtUtc,
          DateTime.utc(2026, 10, 15, 7, 4, 56, 100),
        );
        expect(
          first.projectRelationship!.stageAliases[2].displayName,
          ' Synthetic alias ',
        );
        expect(
          first.contactLinks.single.contactId,
          'synthetic contact/not-a-uuid',
        );
        expect(first.contactLinks.single.responseLevel, isNull);
        expect(first.contactLinks.single.mergeGenerationId, _oldGenerationId);
        expect(second.contactLinks.single.mergeGenerationId, isNull);
        expect(
          second.institutionRelationships.single.status,
          TargetInstitutionRelationshipStatus.ended,
        );
        expect(
          second.institutionRelationships.single.endedAtUtc!.microsecond,
          457,
        );
        expect(first.institutionRelationships.single.endedAtUtc, isNull);
      },
    );
  }

  test('accepts empty facts and retains deep immutable lists', () async {
    final projection = _ready(
      await _read(
        _gateway(_Identity(), MockClient((_) async => _response(_wire()))),
      ),
    );
    final source = projection.sources.first;
    expect(() => projection.sources.clear(), throwsUnsupportedError);
    expect(() => source.contactLinks.clear(), throwsUnsupportedError);
    expect(
      () => source.institutionRelationships.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => source.projectRelationship!.stageAliases.clear(),
      throwsUnsupportedError,
    );
    final wire = _wire();
    _source(wire)['project_relationship'] = null;
    _source(wire)['contact_links'] = [];
    _source(wire)['institution_relationships'] = [];
    final empty = _ready(
      await _read(
        _gateway(_Identity(), MockClient((_) async => _response(wire))),
      ),
    ).sources.first;
    expect(empty.projectRelationship, isNull);
    expect(empty.contactLinks, isEmpty);
    expect(empty.institutionRelationships, isEmpty);
    expect(
      () => empty.contactLinks.add(source.contactLinks.first),
      throwsUnsupportedError,
    );
  });

  test(
    'copies model list inputs instead of exposing mutable constructor aliases',
    () {
      final aliases = <PromotionTargetStageAlias>[];
      final relationship = PersonalTargetMergeProjectRelationship(
        targetId: _firstId,
        projectId: _projectId,
        stage: 0,
        displayStage: 0,
        lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
        followUpNote: null,
        revisionNumber: 1,
        updatedAtUtc: DateTime.utc(2026),
        stageAliases: aliases,
      );
      aliases.add(
        const PromotionTargetStageAlias(
          stage: 0,
          displayStage: 0,
          displayName: null,
        ),
      );
      expect(relationship.stageAliases, isEmpty);
      expect(
        () => relationship.stageAliases.add(aliases.first),
        throwsUnsupportedError,
      );
    },
  );

  test('requires no-store JSON UTF-8 and one exact root key', () async {
    for (final headers in [
      {'content-type': 'application/json; charset=utf-8'},
      {
        'cache-control': 'private',
        'content-type': 'application/json; charset=utf-8',
      },
      {'cache-control': 'no-store', 'content-type': 'text/plain'},
      {
        'cache-control': 'no-store',
        'content-type': 'application/json; charset=utf-16',
      },
    ]) {
      final gateway = _gateway(
        _Identity(),
        MockClient((_) async => _response(_wire(), headers: headers)),
      );
      _failure(
        await _read(gateway),
        PersonalTargetMergeProjectionFailure.invalidResponse,
      );
    }
    for (final bytes in [
      <int>[0xff, 0xfe],
      utf8.encode('{'),
      utf8.encode('[]'),
      utf8.encode('{"projection":null}'),
      utf8.encode(jsonEncode({..._wire(), 'unexpected': true})),
    ]) {
      final gateway = _gateway(
        _Identity(),
        MockClient(
          (_) async => http.Response.bytes(bytes, 200, headers: _headers),
        ),
      );
      _failure(
        await _read(gateway),
        PersonalTargetMergeProjectionFailure.invalidResponse,
      );
    }
  });

  final layers = <(String, _Document Function(_Document), String)>[
    ('projection', _projection, 'retained_target_id'),
    ('source', _source, 'target_id'),
    ('profile', (wire) => _source(wire)['profile'] as _Document, 'phone'),
    ('project relationship', _relationship, 'history'),
    (
      'alias',
      (wire) => (_relationship(wire)['stage_aliases'] as List<_Document>)[0],
      'display_name',
    ),
    ('contact link', _link, 'merge_generation_id'),
    ('institution summary', _institution, 'ended_at'),
  ];
  for (final (name, layer, key) in layers) {
    for (final missing in [false, true]) {
      test('rejects $name ${missing ? 'missing' : 'unknown'} keys', () async {
        final wire = _wire();
        if (missing) {
          layer(wire).remove(key);
        } else {
          layer(wire)['unexpected'] = 'synthetic';
        }
        _failure(
          await _read(
            _gateway(_Identity(), MockClient((_) async => _response(wire))),
          ),
          PersonalTargetMergeProjectionFailure.invalidResponse,
        );
      });
    }
  }

  final mutations = <(String, void Function(_Document))>[
    ('workspace scope', (w) => _projection(w)['workspace_id'] = _partnerId),
    ('project scope', (w) => _projection(w)['project_id'] = _partnerId),
    (
      'generation scope',
      (w) => _projection(w)['generation_id'] = _oldGenerationId,
    ),
    ('type', (w) => _projection(w)['target_type'] = 'organization'),
    ('pair length', (w) => (_projection(w)['sources'] as List).removeLast()),
    (
      'pair order',
      (w) => _projection(w)['sources'] = (_projection(w)['sources'] as List)
          .reversed
          .toList(),
    ),
    (
      'pair duplicate',
      (w) => (_projection(w)['sources'] as List)[1] = _source(w),
    ),
    (
      'profile id',
      (w) => (_source(w)['profile'] as _Document)['target_id'] = _secondId,
    ),
    (
      'profile type',
      (w) =>
          (_source(w)['profile'] as _Document)['target_type'] = 'institution',
    ),
    (
      'profile text',
      (w) => (_source(w)['profile'] as _Document)['display_name'] = ' ',
    ),
    (
      'profile timestamp',
      (w) => (_source(w)['profile'] as _Document)['created_at'] =
          '2026-02-30T12:00:00Z',
    ),
    (
      'retained outside pair',
      (w) => _projection(w)['retained_target_id'] = _partnerId,
    ),
    (
      'name source outside pair',
      (w) => _projection(w)['display_name_source_target_id'] = _partnerId,
    ),
    (
      'phone source outside pair',
      (w) => _projection(w)['phone_source_target_id'] = _partnerId,
    ),
    (
      'email source outside pair',
      (w) => _projection(w)['email_source_target_id'] = _partnerId,
    ),
    (
      'name source value',
      (w) => _projection(w)['display_name_source_target_id'] = _firstId,
    ),
    (
      'phone NULL fallback',
      (w) => _projection(w)['phone'] = ' +1 312 555 0123 ',
    ),
    (
      'email NULL fallback',
      (w) => _projection(w)['email'] = 'synthetic@example.test',
    ),
    (
      'minimum microsecond due',
      (w) => _projection(w)['review_due_at_utc'] = _secondDue,
    ),
    (
      'due six digits',
      (w) => _source(w)['review_due_at_utc'] = '2027-10-15T12:34:56.123Z',
    ),
    (
      'due calendar',
      (w) => _source(w)['review_due_at_utc'] = '2027-02-30T12:34:56.123455Z',
    ),
    ('relationship target', (w) => _relationship(w)['target_id'] = _secondId),
    (
      'relationship project',
      (w) => _relationship(w)['project_id'] = _partnerId,
    ),
    ('relationship stage', (w) => _relationship(w)['stage'] = 5),
    (
      'relationship display stage',
      (w) => _relationship(w)['display_stage'] = 4,
    ),
    (
      'relationship lifecycle',
      (w) => _relationship(w)['lifecycle_status'] = ['active'],
    ),
    ('relationship revision', (w) => _relationship(w)['revision_number'] = 0),
    ('relationship history', (w) => _relationship(w)['history'] = [{}]),
    ('alias count', (w) => _relationship(w)['stage_aliases'] = []),
    (
      'alias stage',
      (w) =>
          (_relationship(w)['stage_aliases'] as List<_Document>)[1]['stage'] =
              0,
    ),
    (
      'alias display stage',
      (w) =>
          (_relationship(w)['stage_aliases']
                  as List<_Document>)[1]['display_stage'] =
              1,
    ),
    (
      'alias label',
      (w) =>
          (_relationship(w)['stage_aliases']
                  as List<_Document>)[1]['display_name'] =
              false,
    ),
    ('contact list', (w) => _source(w)['contact_links'] = {}),
    ('contact text id', (w) => _link(w)['contact_id'] = 10),
    ('contact target', (w) => _link(w)['promotion_target_id'] = _secondId),
    ('contact revision', (w) => _link(w)['revision_number'] = 1.5),
    ('contact response', (w) => _link(w)['response_level'] = 5),
    ('contact consent', (w) => _link(w)['follow_up_consent'] = ['yes']),
    (
      'contact representative boolean',
      (w) => _link(w)['institution_representative_confirmed'] = 1,
    ),
    (
      'contact project-entry boolean',
      (w) => _link(w)['confirmed_project_entry'] = 'true',
    ),
    ('contact generation', (w) => _link(w)['merge_generation_id'] = 'current'),
    ('institution list', (w) => _source(w)['institution_relationships'] = null),
    (
      'institution endpoint',
      (w) => _institution(w)['person_target_id'] = _secondId,
    ),
    (
      'institution equal endpoints',
      (w) => _institution(w)['institution_target_id'] = _firstId,
    ),
    (
      'institution kind',
      (w) => _institution(w)['relationship_kind'] = 'unknown',
    ),
    (
      'institution other role',
      (w) => _institution(w)['relationship_kind'] = 'other',
    ),
    ('institution status', (w) => _institution(w)['status'] = 'ended'),
    ('institution revision', (w) => _institution(w)['revision_number'] = 0),
    ('institution history', (w) => _institution(w)['history'] = []),
    (
      'institution partner profile',
      (w) => _institution(w)['profile'] = {'display_name': 'synthetic'},
    ),
    (
      'institution earlier microsecond end',
      (w) {
        _institution(w)['ended_at'] = '2026-10-14T10:00:00.123455Z';
        _institution(w)['status'] = 'ended';
      },
    ),
  ];
  for (final (name, mutate) in mutations) {
    test('rejects $name without returning response data', () async {
      final wire = _wire();
      mutate(wire);
      _failure(
        await _read(
          _gateway(_Identity(), MockClient((_) async => _response(wire))),
        ),
        PersonalTargetMergeProjectionFailure.invalidResponse,
      );
    });
  }

  test(
    'maps statuses without body values and refreshes 401 only once',
    () async {
      for (final (status, failure) in [
        (400, PersonalTargetMergeProjectionFailure.invalidRequest),
        (401, PersonalTargetMergeProjectionFailure.unauthenticated),
        (403, PersonalTargetMergeProjectionFailure.forbidden),
        (503, PersonalTargetMergeProjectionFailure.serviceUnavailable),
        (500, PersonalTargetMergeProjectionFailure.invalidResponse),
      ]) {
        final identity = _Identity();
        var requests = 0;
        final gateway = _gateway(
          identity,
          MockClient((_) async {
            requests++;
            return http.Response('synthetic private SQL detail', status);
          }),
        );
        _failure(await _read(gateway), failure);
        expect(identity.forceRefresh, status == 401 ? [false, true] : [false]);
        expect(requests, status == 401 ? 2 : 1);
      }
      final identity = _Identity();
      var requests = 0;
      final gateway = _gateway(
        identity,
        MockClient(
          (_) async =>
              ++requests == 1 ? http.Response('', 401) : _response(_wire()),
        ),
      );
      expect(await _read(gateway), isA<PersonalTargetMergeProjectionReady>());
      expect(identity.forceRefresh, [false, true]);
    },
  );

  test(
    'does not issue HTTP for wrong exact identity, stale fence or malformed scope',
    () async {
      final identity = _Identity();
      var requests = 0;
      final gateway = _gateway(
        identity,
        MockClient((_) async {
          requests++;
          return _response(_wire());
        }),
      );
      _failure(
        await _read(gateway, expectedSubject: 'owner'),
        PersonalTargetMergeProjectionFailure.unauthenticated,
      );
      _failure(
        await _read(gateway, current: () => false),
        PersonalTargetMergeProjectionFailure.requestInvalidated,
      );
      for (final scope in [
        ('', _projectId, _generationId),
        (_workspaceId, 'bad', _generationId),
        (_workspaceId, _projectId, '../bad'),
      ]) {
        _failure(
          await gateway.read(
            expectedSubject: _subject,
            workspaceId: scope.$1,
            projectId: scope.$2,
            generationId: scope.$3,
            requestIsCurrent: () => true,
          ),
          PersonalTargetMergeProjectionFailure.invalidRequest,
        );
      }
      expect(requests, 0);
      expect(identity.forceRefresh, isEmpty);
    },
  );

  test(
    'maps token rejection, HTTP error and token/response timeouts',
    () async {
      for (final code in [
        IdentityFailureCode.sessionMissing,
        IdentityFailureCode.networkUnavailable,
      ]) {
        final identity = _Identity()
          ..token = (_) async => IdentityRejected(IdentityFailure(code: code));
        final gateway = _gateway(
          identity,
          MockClient((_) async => fail('must not request')),
        );
        _failure(
          await _read(gateway),
          code == IdentityFailureCode.networkUnavailable
              ? PersonalTargetMergeProjectionFailure.networkUnavailable
              : PersonalTargetMergeProjectionFailure.unauthenticated,
        );
      }
      final network = _gateway(
        _Identity(),
        MockClient(
          (_) async => throw http.ClientException('synthetic private detail'),
        ),
      );
      _failure(
        await _read(network),
        PersonalTargetMergeProjectionFailure.networkUnavailable,
      );
      for (final tokenTimeout in [false, true]) {
        final identity = _Identity();
        if (tokenTimeout) {
          identity.token = (_) =>
              Completer<IdentityResult<IdentityAccessToken>>().future;
        }
        final gateway = _gateway(
          identity,
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(milliseconds: 5),
        );
        _failure(
          await _read(gateway),
          PersonalTargetMergeProjectionFailure.networkUnavailable,
        );
      }
    },
  );

  for (final duringToken in [true, false]) {
    for (final invalidation in [
      'ABA',
      'signed out',
      'stream error',
      'stream done',
      'caller',
      'close',
    ]) {
      test(
        '$invalidation during ${duringToken ? 'token' : 'response'} permanently invalidates the request',
        () async {
          final identity = _Identity();
          final pending = Completer<void>();
          final release = Completer<void>();
          var current = true;
          var requests = 0;
          if (duringToken) {
            identity.token = (_) async {
              pending.complete();
              await release.future;
              return _token();
            };
          }
          final gateway = _gateway(
            identity,
            MockClient((_) async {
              requests++;
              if (!duringToken) {
                pending.complete();
                await release.future;
              }
              return _response(_wire());
            }),
          );
          final result = _read(gateway, current: () => current);
          await pending.future;
          switch (invalidation) {
            case 'ABA':
              identity.emit(_snapshot('other'));
              identity.emit(_snapshot(_subject));
            case 'signed out':
              identity.emit(const IdentitySnapshot.signedOut());
            case 'stream error':
              identity.controller.addError(
                StateError('synthetic stream detail'),
              );
            case 'stream done':
              await identity.controller.close();
            case 'caller':
              current = false;
            case 'close':
              await gateway.close();
          }
          release.complete();
          _failure(
            await result,
            PersonalTargetMergeProjectionFailure.requestInvalidated,
          );
          expect(requests, duringToken ? 0 : 1);
          expect(identity.closed, isFalse);
        },
      );
    }
  }

  test('401 refresh has the same sticky identity fence', () async {
    final identity = _Identity();
    final refreshing = Completer<void>();
    final release = Completer<void>();
    identity.token = (forceRefresh) async {
      if (forceRefresh) {
        refreshing.complete();
        await release.future;
      }
      return _token();
    };
    var requests = 0;
    final gateway = _gateway(
      identity,
      MockClient((_) async {
        requests++;
        return http.Response('', 401);
      }),
    );
    final result = _read(gateway);
    await refreshing.future;
    identity.emit(_snapshot('other'));
    identity.emit(_snapshot(_subject));
    release.complete();
    _failure(
      await result,
      PersonalTargetMergeProjectionFailure.requestInvalidated,
    );
    expect(requests, 1);
    expect(identity.forceRefresh, [false, true]);
  });

  test(
    'same subject metadata refresh is allowed; close prevents new requests and borrows identity',
    () async {
      final identity = _Identity();
      var requests = 0;
      final gateway = _gateway(
        identity,
        MockClient((_) async {
          requests++;
          identity.emit(
            IdentitySnapshot(
              stage: IdentityStage.signedIn,
              principal: const IdentityPrincipal(
                externalSubject: _subject,
                email: 'updated@example.test',
              ),
              expiresAt: DateTime.utc(2035),
            ),
          );
          return _response(_wire());
        }),
      );
      expect(await _read(gateway), isA<PersonalTargetMergeProjectionReady>());
      await gateway.close();
      await gateway.close();
      _failure(
        await _read(gateway),
        PersonalTargetMergeProjectionFailure.requestInvalidated,
      );
      expect(requests, 1);
      expect(identity.closed, isFalse);
    },
  );

  test(
    'validates backend URI and offers a deferred unavailable gateway',
    () async {
      expect(
        () => HttpPersonalTargetMergeProjectionGateway(
          baseUri: Uri.parse('http://remote.example.test'),
          identitySession: _Identity(),
          client: MockClient((_) async => _response(_wire())),
        ),
        throwsFormatException,
      );
      const deferred = DeferredPersonalTargetMergeProjectionGateway();
      _failure(
        await _read(deferred),
        PersonalTargetMergeProjectionFailure.networkUnavailable,
      );
      await deferred.close();
    },
  );
}

HttpPersonalTargetMergeProjectionGateway _gateway(
  _Identity identity,
  http.Client client, {
  Duration timeout = const Duration(seconds: 15),
}) {
  final gateway = HttpPersonalTargetMergeProjectionGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: identity,
    client: client,
    timeout: timeout,
  );
  addTearDown(gateway.close);
  addTearDown(identity.close);
  return gateway;
}

Future<PersonalTargetMergeProjectionResult> _read(
  PersonalTargetMergeProjectionGateway gateway, {
  String expectedSubject = _subject,
  bool Function()? current,
}) => gateway.read(
  expectedSubject: expectedSubject,
  workspaceId: _workspaceId,
  projectId: _projectId,
  generationId: _generationId,
  requestIsCurrent: current ?? () => true,
);

PersonalTargetMergeProjection _ready(
  PersonalTargetMergeProjectionResult result,
) {
  expect(result, isA<PersonalTargetMergeProjectionReady>());
  return (result as PersonalTargetMergeProjectionReady).projection;
}

void _failure(
  PersonalTargetMergeProjectionResult result,
  PersonalTargetMergeProjectionFailure failure,
) {
  expect(result, isA<PersonalTargetMergeProjectionRejected>());
  expect((result as PersonalTargetMergeProjectionRejected).failure, failure);
  expect(result.toString(), isNot(contains('synthetic private')));
}

const _headers = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};
http.Response _response(
  _Document wire, {
  Map<String, String> headers = _headers,
}) => http.Response.bytes(utf8.encode(jsonEncode(wire)), 200, headers: headers);

_Document _projection(_Document wire) => wire['projection'] as _Document;
_Document _source(_Document wire) =>
    (_projection(wire)['sources'] as List<_Document>)[0];
_Document _relationship(_Document wire) =>
    _source(wire)['project_relationship'] as _Document;
_Document _link(_Document wire) =>
    (_source(wire)['contact_links'] as List<_Document>)[0];
_Document _institution(_Document wire) =>
    (_source(wire)['institution_relationships'] as List<_Document>)[0];

_Document _wire([String type = 'person']) => {
  'projection': <String, Object?>{
    'generation_id': _generationId,
    'workspace_id': _workspaceId,
    'project_id': _projectId,
    'target_type': type,
    'retained_target_id': _firstId,
    'display_name': ' Synthetic source B ',
    'phone': null,
    'email': null,
    'display_name_source_target_id': _secondId,
    'phone_source_target_id': _secondId,
    'email_source_target_id': _firstId,
    'review_due_at_utc': _firstDue,
    'sources': <_Document>[
      for (var index = 0; index < 2; index++)
        {
          'target_id': index == 0 ? _firstId : _secondId,
          'profile': <String, Object?>{
            'target_id': index == 0 ? _firstId : _secondId,
            'target_type': type,
            'display_name': index == 0
                ? 'Synthetic source A'
                : ' Synthetic source B ',
            'phone': index == 0 ? ' +1 312 555 0123 ' : null,
            'email': index == 0 ? null : 'synthetic@example.test',
            'created_at': '2026-10-15T07:34:56.123456-05:00',
          },
          'review_due_at_utc': index == 0 ? _firstDue : _secondDue,
          'project_relationship': <String, Object?>{
            'target_id': index == 0 ? _firstId : _secondId,
            'project_id': _projectId,
            'stage': index * 3,
            'display_stage': index * 6,
            'lifecycle_status': index == 0 ? 'active' : 'paused',
            'follow_up_note': null,
            'revision_number': 2,
            'updated_at': '2026-10-15T12:34:56.1+05:30',
            'history': [],
            'stage_aliases': <_Document>[
              for (var stage = 0; stage < 5; stage++)
                {
                  'stage': stage,
                  'display_stage': stage * 2,
                  'display_name': stage == 2 ? ' Synthetic alias ' : null,
                },
            ],
          },
          'contact_links': <_Document>[
            {
              'contact_id': 'synthetic contact/not-a-uuid',
              'revision_number': 3,
              'promotion_target_id': index == 0 ? _firstId : _secondId,
              'response_level': index == 0 ? null : 4,
              'follow_up_consent': 'unknown',
              'institution_representative_confirmed': false,
              'confirmed_project_entry': true,
              'merge_generation_id': index == 0 ? _oldGenerationId : null,
            },
          ],
          'institution_relationships': <_Document>[
            {
              'relationship_id': index == 0 ? _firstId : _secondId,
              'person_target_id': type == 'person'
                  ? (index == 0 ? _firstId : _secondId)
                  : _partnerId,
              'institution_target_id': type == 'institution'
                  ? (index == 0 ? _firstId : _secondId)
                  : _partnerId,
              'relationship_kind': 'membership_affiliation',
              'role_description': null,
              'started_at': '2026-10-14T10:00:00.123456+00:00',
              'ended_at': index == 0 ? null : '2026-10-14T10:00:00.123457Z',
              'status': index == 0 ? 'active' : 'ended',
              'revision_number': index + 1,
            },
          ],
        },
    ],
  },
};

IdentitySnapshot _snapshot(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: subject, email: null),
);
IdentitySuccess<IdentityAccessToken> _token() => const IdentitySuccess(
  IdentityAccessToken(value: 'synthetic-token', expiresAt: null),
);

final class _Identity implements IdentitySession {
  final controller = StreamController<IdentitySnapshot>.broadcast(sync: true);
  IdentitySnapshot _current = _snapshot(_subject);
  final forceRefresh = <bool>[];
  Future<IdentityResult<IdentityAccessToken>> Function(bool)? token;
  bool closed = false;
  void emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    controller.add(snapshot);
  }

  @override
  IdentitySnapshot get current => _current;
  @override
  Stream<IdentitySnapshot> get changes => controller.stream;
  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    this.forceRefresh.add(forceRefresh);
    return token == null ? _token() : await token!(forceRefresh);
  }

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity operation');
}
