import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/http_personal_target_merge_split_plan_gateway.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_split_plan.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

const _subject = ' owner ';
const _workspaceId = '7ec00000-0000-4000-8000-000000000001';
const _projectId = '7ec00000-0000-4000-8000-000000000002';
const _generationId = '7ec00000-0000-4000-8000-000000000003';
const _firstId = '7ec00000-0000-4000-8000-000000000011';
const _secondId = '7ec00000-0000-4000-8000-000000000012';
const _partnerId = '7ec00000-0000-4000-8000-000000000013';
const _otherProjectId = '7ec00000-0000-4000-8000-000000000014';
const _relationshipId = '7ec00000-0000-4000-8000-000000000015';
const _oldGenerationId = '7ec00000-0000-4000-8000-000000000099';
const _due = '2027-10-15T12:34:56.123455Z';
const _updatedAt = '2026-10-14T10:00:00.123456Z';
const _contactId = ' 接触 / | : [ ] 😀  ';
const _fingerprint =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
typedef _Document = Map<String, Object?>;

void main() {
  test(
    'uses the split-plan GET with no query, body or caller identity fields',
    () async {
      final identity = _Identity();
      final gateway = _gateway(
        identity,
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://backend.example.test/v1/projects/$_projectId/promotion-target-merges/$_generationId/split-plan',
          );
          expect(request.url.hasQuery, isFalse);
          expect(request.body, isEmpty);
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          expect(request.headers['accept'], 'application/json');
          expect(request.headers.containsKey('content-type'), isFalse);
          return _response(_wire());
        }),
      );
      final plan = _ready(await _read(gateway));
      expect(plan.generationId, _generationId);
      expect(plan.workspaceId, _workspaceId);
      expect(plan.projectId, _projectId);
      expect(plan.memberTargetIds, [_firstId, _secondId]);
      expect(plan.reviewDueAtUtc, DateTime.parse(_due));
      expect(plan.reviewDueAtUtc.microsecond, 455);
      expect(plan.factFingerprint, _fingerprint);
      expect(plan.factCount, 8);
      expect(identity.forceRefresh, [false]);
    },
  );

  for (final type in ['person', 'institution']) {
    test(
      'preserves $type native variants, history, cross-project facts and database order',
      () async {
        final plan = _ready(
          await _read(
            _gateway(
              _Identity(),
              MockClient((_) async => _response(_wire(type))),
            ),
          ),
        );
        expect(plan.targetType.storageValue, type);
        expect(plan.facts.map((fact) => fact.metadata.runtimeType), [
          PersonalTargetMergeSplitPlanProjectRevision,
          PersonalTargetMergeSplitPlanContactLink,
          PersonalTargetMergeSplitPlanInstitutionRevision,
          PersonalTargetMergeSplitPlanProjectRelationship,
          PersonalTargetMergeSplitPlanInstitutionRelationship,
          PersonalTargetMergeSplitPlanContactLink,
          PersonalTargetMergeSplitPlanProjectRevision,
          PersonalTargetMergeSplitPlanContactLink,
        ]);
        final revision =
            plan.facts[0].metadata
                as PersonalTargetMergeSplitPlanProjectRevision;
        expect(revision.promotionTargetId, _firstId);
        expect(revision.projectId, _otherProjectId);
        expect(revision.revisionNumber, 1);
        final contact =
            plan.facts[1].metadata as PersonalTargetMergeSplitPlanContactLink;
        expect(contact.contactId, _contactId);
        expect(contact.revisionNumber, 1);
        expect(contact.promotionTargetId, _firstId);
        final institutionRevision =
            plan.facts[2].metadata
                as PersonalTargetMergeSplitPlanInstitutionRevision;
        expect(institutionRevision.endpoint.name, type);
        expect(institutionRevision.relationshipId, _relationshipId);
        expect(institutionRevision.revisionNumber, 1);
        expect(institutionRevision.otherMergeGenerationId, _oldGenerationId);
        expect(
          institutionRevision.personTargetId,
          type == 'person' ? _firstId : _partnerId,
        );
        expect(
          institutionRevision.institutionTargetId,
          type == 'institution' ? _firstId : _partnerId,
        );
        final relationship =
            plan.facts[3].metadata
                as PersonalTargetMergeSplitPlanProjectRelationship;
        expect(relationship.currentRevision, 4);
        expect(relationship.projectId, _otherProjectId);
        expect(relationship.updatedAtUtc, DateTime.parse(_updatedAt));
        expect(relationship.updatedAtUtc.microsecond, 456);
        final institution =
            plan.facts[4].metadata
                as PersonalTargetMergeSplitPlanInstitutionRelationship;
        expect(institution.endpoint.name, type);
        expect(institution.currentRevision, 2);
        expect(institution.otherMergeGenerationId, isNull);
        expect(institution.updatedAtUtc.microsecond, 456);
        expect(
          (plan.facts[5].metadata as PersonalTargetMergeSplitPlanContactLink)
              .revisionNumber,
          3,
        );
        expect(
          (plan.facts[6].metadata
                  as PersonalTargetMergeSplitPlanProjectRevision)
              .revisionNumber,
          3,
        );
        expect(plan.facts[7].sourceTargetId, _secondId);
        expect(
          (plan.facts[7].metadata as PersonalTargetMergeSplitPlanContactLink)
              .contactId,
          isEmpty,
        );
      },
    );
  }

  test(
    'retains empty, whitespace, separator and Unicode contact IDs without normalization',
    () async {
      for (final id in ['', '   ', _contactId, 'a|1|$_firstId', '\t接触\n']) {
        final wire = _wire();
        _metadata(wire, 1)[1] = id;
        _metadata(wire, 5)[1] = id;
        final plan = _ready(
          await _read(
            _gateway(_Identity(), MockClient((_) async => _response(wire))),
          ),
        );
        expect(
          (plan.facts[1].metadata as PersonalTargetMergeSplitPlanContactLink)
              .contactId,
          id,
        );
        expect(
          (plan.facts[5].metadata as PersonalTargetMergeSplitPlanContactLink)
              .contactId,
          id,
        );
      }
    },
  );

  test(
    'accepts empty facts and copies constructor lists into immutable results',
    () async {
      final wire = _wire();
      _plan(wire)['facts'] = <_Document>[];
      _plan(wire)['fact_count'] = 0;
      final empty = _ready(
        await _read(
          _gateway(_Identity(), MockClient((_) async => _response(wire))),
        ),
      );
      expect(empty.facts, isEmpty);
      final members = <String>[_firstId, _secondId];
      final facts = <PersonalTargetMergeSplitPlanFact>[
        const PersonalTargetMergeSplitPlanFact(
          sourceTargetId: _firstId,
          metadata: PersonalTargetMergeSplitPlanContactLink(
            contactId: _contactId,
            revisionNumber: 1,
            promotionTargetId: _firstId,
          ),
        ),
      ];
      final plan = PersonalTargetMergeSplitPlan(
        generationId: _generationId,
        workspaceId: _workspaceId,
        projectId: _projectId,
        targetType: PromotionTargetType.person,
        memberTargetIds: members,
        reviewDueAtUtc: DateTime.parse(_due),
        factCount: 1,
        factFingerprint: _fingerprint,
        facts: facts,
      );
      members.clear();
      facts.clear();
      expect(plan.memberTargetIds, [_firstId, _secondId]);
      expect(plan.facts, hasLength(1));
      expect(() => plan.memberTargetIds.clear(), throwsUnsupportedError);
      expect(() => plan.facts.clear(), throwsUnsupportedError);
      expect(() => empty.facts.add(plan.facts.first), throwsUnsupportedError);
    },
  );

  test(
    'preserves UUID spelling while comparing UUID scope and fact keys without case',
    () async {
      final wire = _wire();
      _plan(wire)['workspace_id'] = _workspaceId.toUpperCase();
      _plan(wire)['generation_id'] = _generationId.toUpperCase();
      _plan(wire)['member_target_ids'] = [_firstId.toUpperCase(), _secondId];
      _fact(wire, 0)['source_target_id'] = _firstId.toUpperCase();
      _metadata(wire, 0)[1] = _firstId.toUpperCase();
      final plan = _ready(
        await _read(
          _gateway(_Identity(), MockClient((_) async => _response(wire))),
        ),
      );
      expect(plan.workspaceId, _workspaceId.toUpperCase());
      expect(plan.generationId, _generationId.toUpperCase());
      expect(plan.memberTargetIds.first, _firstId.toUpperCase());
      expect(plan.facts.first.sourceTargetId, _firstId.toUpperCase());
      expect(
        (plan.facts.first.metadata
                as PersonalTargetMergeSplitPlanProjectRevision)
            .promotionTargetId,
        _firstId.toUpperCase(),
      );
    },
  );

  test(
    'accepts canonical zero microseconds and past snapshot due without a client clock gate',
    () async {
      final wire = _wire();
      _plan(wire)['review_due_at_utc'] = '2020-01-01T00:00:00.000000Z';
      _metadata(wire, 3)[4] = '2020-01-01T00:00:00.123000Z';
      final plan = _ready(
        await _read(
          _gateway(_Identity(), MockClient((_) async => _response(wire))),
        ),
      );
      expect(plan.reviewDueAtUtc, DateTime.utc(2020));
      expect(
        (plan.facts[3].metadata
                as PersonalTargetMergeSplitPlanProjectRelationship)
            .updatedAtUtc,
        DateTime.utc(2020, 1, 1, 0, 0, 0, 123),
      );
    },
  );

  test('requires no-store JSON UTF-8 with one exact root key', () async {
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
      _failure(
        await _read(
          _gateway(
            _Identity(),
            MockClient((_) async => _response(_wire(), headers: headers)),
          ),
        ),
        PersonalTargetMergeSplitPlanFailure.invalidResponse,
      );
    }
    for (final bytes in [
      <int>[0xff, 0xfe],
      utf8.encode('{'),
      utf8.encode('[]'),
      utf8.encode('{"split_plan":null}'),
      utf8.encode(jsonEncode({..._wire(), 'unexpected': true})),
      utf8.encode(jsonEncode({'projection': _plan(_wire())})),
    ]) {
      _failure(
        await _read(
          _gateway(
            _Identity(),
            MockClient(
              (_) async => http.Response.bytes(bytes, 200, headers: _headers),
            ),
          ),
        ),
        PersonalTargetMergeSplitPlanFailure.invalidResponse,
      );
    }
  });

  for (final key in [
    'generation_id',
    'workspace_id',
    'project_id',
    'target_type',
    'member_target_ids',
    'review_due_at_utc',
    'fact_count',
    'fact_fingerprint',
    'facts',
  ]) {
    test('rejects missing plan key $key', () async {
      final wire = _wire();
      _plan(wire).remove(key);
      await _invalid(wire);
    });
  }
  for (final key in ['source_target_id', 'metadata']) {
    test('rejects missing fact key $key', () async {
      final wire = _wire();
      _fact(wire, 0).remove(key);
      await _invalid(wire);
    });
  }

  final mutations = <(String, void Function(_Document))>[
    (
      'extra plan business field',
      (w) => _plan(w)['display_name'] = 'synthetic private name',
    ),
    ('workspace scope', (w) => _plan(w)['workspace_id'] = _partnerId),
    ('project scope', (w) => _plan(w)['project_id'] = _partnerId),
    ('generation scope', (w) => _plan(w)['generation_id'] = _oldGenerationId),
    ('target type', (w) => _plan(w)['target_type'] = 'organization'),
    ('members type', (w) => _plan(w)['member_target_ids'] = {}),
    ('member count', (w) => _plan(w)['member_target_ids'] = [_firstId]),
    (
      'member UUID',
      (w) => _plan(w)['member_target_ids'] = ['target', _secondId],
    ),
    (
      'member UUID newline',
      (w) => _plan(w)['member_target_ids'] = ['$_firstId\n', _secondId],
    ),
    (
      'member order',
      (w) => _plan(w)['member_target_ids'] = [_secondId, _firstId],
    ),
    (
      'member duplicate',
      (w) => _plan(w)['member_target_ids'] = [_firstId, _firstId.toUpperCase()],
    ),
    ('fact count mismatch', (w) => _plan(w)['fact_count'] = 0),
    ('negative fact count', (w) => _plan(w)['fact_count'] = -1),
    ('fractional fact count', (w) => _plan(w)['fact_count'] = 1.5),
    ('unsafe fact count', (w) => _plan(w)['fact_count'] = 9007199254740992),
    ('fingerprint type', (w) => _plan(w)['fact_fingerprint'] = []),
    ('fingerprint length', (w) => _plan(w)['fact_fingerprint'] = 'abc'),
    ('fingerprint characters', (w) => _plan(w)['fact_fingerprint'] = 'z' * 64),
    (
      'fingerprint newline',
      (w) => _plan(w)['fact_fingerprint'] = '$_fingerprint\n',
    ),
    ('fact list', (w) => _plan(w)['facts'] = {}),
    ('fact object', (w) => _facts(w)[0] = null),
    ('fact extra business value', (w) => _fact(w, 0)['response_level'] = 2),
    ('fact source', (w) => _fact(w, 0)['source_target_id'] = _partnerId),
    ('metadata type', (w) => _fact(w, 0)['metadata'] = {}),
    ('metadata empty', (w) => _fact(w, 0)['metadata'] = []),
    ('metadata tag type', (w) => _metadata(w, 0)[0] = ['project_revision']),
    ('metadata unknown tag', (w) => _metadata(w, 0)[0] = 'contact_revision'),
    ('contact ID type', (w) => _metadata(w, 1)[1] = 12),
    ('contact source', (w) => _metadata(w, 1)[3] = _secondId),
    ('contact revision', (w) => _metadata(w, 1)[2] = 0),
    ('project revision source', (w) => _metadata(w, 0)[1] = _secondId),
    ('project revision project UUID', (w) => _metadata(w, 0)[2] = 'project'),
    ('project revision number', (w) => _metadata(w, 0)[3] = 1.5),
    ('project relationship source', (w) => _metadata(w, 3)[1] = _secondId),
    ('project relationship project UUID', (w) => _metadata(w, 3)[2] = null),
    (
      'project relationship revision',
      (w) => _metadata(w, 3)[3] = 9007199254740992,
    ),
    ('institution relationship ID', (w) => _metadata(w, 4)[1] = 'relationship'),
    (
      'institution relationship endpoint',
      (w) => _metadata(w, 4)[2] = _secondId,
    ),
    (
      'institution relationship equal endpoints',
      (w) => _metadata(w, 4)[3] = _firstId,
    ),
    ('institution relationship revision', (w) => _metadata(w, 4)[4] = 0),
    (
      'institution relationship other binding',
      (w) => _metadata(w, 4)[6] = 'old',
    ),
    ('institution revision ID', (w) => _metadata(w, 2)[1] = false),
    ('institution revision endpoint', (w) => _metadata(w, 2)[3] = _secondId),
    (
      'institution revision equal endpoints',
      (w) => _metadata(w, 2)[4] = _firstId,
    ),
    ('institution revision number', (w) => _metadata(w, 2)[2] = null),
    ('institution revision other binding', (w) => _metadata(w, 2)[5] = []),
  ];
  for (final (name, mutate) in mutations) {
    test('rejects $name', () async {
      final wire = _wire();
      mutate(wire);
      await _invalid(wire);
    });
  }

  for (final type in ['person', 'institution']) {
    for (final index in [0, 1, 2, 3, 4]) {
      for (final extra in [false, true]) {
        test(
          'rejects $type variant $index ${extra ? 'extra' : 'missing'} array entries',
          () async {
            final wire = _wire(type);
            if (extra) {
              _metadata(wire, index).add('synthetic business value');
            } else {
              _metadata(wire, index).removeLast();
            }
            await _invalid(wire);
          },
        );
      }
    }
    for (final index in [2, 4]) {
      test(
        'rejects $type opposite endpoint in the member pair at $index',
        () async {
          final wire = _wire(type);
          final oppositeIndex = index == 2
              ? (type == 'person' ? 4 : 3)
              : (type == 'person' ? 3 : 2);
          _metadata(wire, index)[oppositeIndex] = _secondId;
          await _invalid(wire);
        },
      );
      test(
        'rejects a $type institution variant for the other endpoint type at $index',
        () async {
          final wire = _wire(type);
          _metadata(wire, index)[0] =
              '${index == 2 ? 'institution_revision' : 'institution_relationship'}_${type == 'person' ? 'institution' : 'person'}';
          await _invalid(wire);
        },
      );
    }
  }

  for (final index in [0, 1, 2, 3, 4]) {
    test(
      'rejects duplicate natural fact key at $index despite changed mutable metadata',
      () async {
        final wire = _wire();
        final duplicate = <Object?>[..._metadata(wire, index)];
        if (index == 3) duplicate[3] = 5;
        if (index == 4) duplicate[4] = 3;
        _facts(wire).add(<String, Object?>{
          'source_target_id': _firstId.toUpperCase(),
          'metadata': duplicate,
        });
        _plan(wire)['fact_count'] = _facts(wire).length;
        await _invalid(wire);
      },
    );
  }

  final badTimestamps = [
    null,
    10,
    '2026-02-30T10:00:00.123456Z',
    '0000-01-01T00:00:00.000000Z',
    '2026-10-14T24:00:00.123456Z',
    '2026-10-14T10:60:00.123456Z',
    '2026-10-14T10:00:60.123456Z',
    '2026-10-14T10:00:00Z',
    '2026-10-14T10:00:00.123Z',
    '2026-10-14T10:00:00.1234567Z',
    '2026-10-14T10:00:00.123456+00:00',
    '2026-10-14T10:00:00.123456Z\n',
  ];
  for (final field in ['due', 'project', 'institution']) {
    test('rejects malformed canonical timestamps in $field', () async {
      for (final timestamp in badTimestamps) {
        final wire = _wire();
        switch (field) {
          case 'due':
            _plan(wire)['review_due_at_utc'] = timestamp;
          case 'project':
            _metadata(wire, 3)[4] = timestamp;
          case 'institution':
            _metadata(wire, 4)[5] = timestamp;
        }
        await _invalid(wire);
      }
    });
  }

  test(
    'maps statuses without private body values and refreshes 401 only once',
    () async {
      for (final (status, failure) in [
        (400, PersonalTargetMergeSplitPlanFailure.invalidRequest),
        (401, PersonalTargetMergeSplitPlanFailure.unauthenticated),
        (403, PersonalTargetMergeSplitPlanFailure.forbidden),
        (503, PersonalTargetMergeSplitPlanFailure.serviceUnavailable),
        (500, PersonalTargetMergeSplitPlanFailure.invalidResponse),
      ]) {
        final identity = _Identity();
        var requests = 0;
        _failure(
          await _read(
            _gateway(
              identity,
              MockClient((_) async {
                requests++;
                return http.Response('synthetic private SQL detail', status);
              }),
            ),
          ),
          failure,
        );
        expect(identity.forceRefresh, status == 401 ? [false, true] : [false]);
        expect(requests, status == 401 ? 2 : 1);
      }
      final identity = _Identity();
      var requests = 0;
      final result = await _read(
        _gateway(
          identity,
          MockClient(
            (_) async =>
                ++requests == 1 ? http.Response('', 401) : _response(_wire()),
          ),
        ),
      );
      expect(result, isA<PersonalTargetMergeSplitPlanReady>());
      expect(identity.forceRefresh, [false, true]);
    },
  );

  test(
    'rejects wrong exact subject, stale caller and malformed scope before HTTP',
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
        PersonalTargetMergeSplitPlanFailure.unauthenticated,
      );
      _failure(
        await _read(gateway, current: () => false),
        PersonalTargetMergeSplitPlanFailure.requestInvalidated,
      );
      for (final scope in [
        ('', _projectId, _generationId),
        (_workspaceId, 'bad', _generationId),
        (_workspaceId, _projectId, '../bad'),
        (_workspaceId, _projectId, '$_generationId\n'),
      ]) {
        _failure(
          await gateway.read(
            expectedSubject: _subject,
            workspaceId: scope.$1,
            projectId: scope.$2,
            generationId: scope.$3,
            requestIsCurrent: () => true,
          ),
          PersonalTargetMergeSplitPlanFailure.invalidRequest,
        );
      }
      expect(requests, 0);
      expect(identity.forceRefresh, isEmpty);
    },
  );

  test(
    'maps token rejection, client errors and token or response timeout',
    () async {
      for (final code in [
        IdentityFailureCode.sessionMissing,
        IdentityFailureCode.networkUnavailable,
      ]) {
        final identity = _Identity()
          ..token = (_) async => IdentityRejected(IdentityFailure(code: code));
        _failure(
          await _read(
            _gateway(
              identity,
              MockClient((_) async => fail('must not request')),
            ),
          ),
          code == IdentityFailureCode.networkUnavailable
              ? PersonalTargetMergeSplitPlanFailure.networkUnavailable
              : PersonalTargetMergeSplitPlanFailure.unauthenticated,
        );
      }
      _failure(
        await _read(
          _gateway(
            _Identity(),
            MockClient(
              (_) async =>
                  throw http.ClientException('synthetic private detail'),
            ),
          ),
        ),
        PersonalTargetMergeSplitPlanFailure.networkUnavailable,
      );
      for (final duringToken in [true, false]) {
        final identity = _Identity();
        if (duringToken) {
          identity.token = (_) =>
              Completer<IdentityResult<IdentityAccessToken>>().future;
        }
        _failure(
          await _read(
            _gateway(
              identity,
              MockClient((_) => Completer<http.Response>().future),
              timeout: const Duration(milliseconds: 5),
            ),
          ),
          PersonalTargetMergeSplitPlanFailure.networkUnavailable,
        );
      }
    },
  );

  for (final synchronous in [true, false]) {
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
          '$invalidation during ${duringToken ? 'token' : 'response'} invalidates ${synchronous ? 'sync' : 'async'} identity requests',
          () async {
            final identity = _Identity(synchronous: synchronous);
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
                  StateError('synthetic private stream detail'),
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
              PersonalTargetMergeSplitPlanFailure.requestInvalidated,
            );
            expect(requests, duringToken ? 0 : 1);
            expect(identity.closed, isFalse);
          },
        );
      }
    }
  }

  test('invalidates an old caller while a newer request completes', () async {
    final identity = _Identity();
    final firstResponse = Completer<http.Response>();
    var calls = 0;
    var generation = 1;
    final gateway = _gateway(
      identity,
      MockClient(
        (_) => ++calls == 1
            ? firstResponse.future
            : Future.value(_response(_wire())),
      ),
    );
    final old = _read(gateway, current: () => generation == 1);
    await Future<void>.delayed(Duration.zero);
    generation++;
    expect(
      await _read(gateway, current: () => generation == 2),
      isA<PersonalTargetMergeSplitPlanReady>(),
    );
    firstResponse.complete(_response(_wire()));
    _failure(await old, PersonalTargetMergeSplitPlanFailure.requestInvalidated);
  });

  test('applies the identity fence during the single forced refresh', () async {
    final identity = _Identity();
    final refreshing = Completer<void>();
    final release = Completer<void>();
    identity.token = (fresh) async {
      if (fresh) {
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
      PersonalTargetMergeSplitPlanFailure.requestInvalidated,
    );
    expect(requests, 1);
    expect(identity.forceRefresh, [false, true]);
  });

  test(
    'keeps same-subject metadata changes and never closes the borrowed identity',
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
      expect(await _read(gateway), isA<PersonalTargetMergeSplitPlanReady>());
      await gateway.close();
      await gateway.close();
      _failure(
        await _read(gateway),
        PersonalTargetMergeSplitPlanFailure.requestInvalidated,
      );
      expect(requests, 1);
      expect(identity.closed, isFalse);
    },
  );

  test(
    'validates the Backend URI and provides an unavailable deferred gateway',
    () async {
      expect(
        () => HttpPersonalTargetMergeSplitPlanGateway(
          baseUri: Uri.parse('http://remote.example.test'),
          identitySession: _Identity(),
          client: MockClient((_) async => _response(_wire())),
        ),
        throwsFormatException,
      );
      const gateway = DeferredPersonalTargetMergeSplitPlanGateway();
      _failure(
        await _read(gateway),
        PersonalTargetMergeSplitPlanFailure.networkUnavailable,
      );
      await gateway.close();
    },
  );
}

HttpPersonalTargetMergeSplitPlanGateway _gateway(
  _Identity identity,
  http.Client client, {
  Duration timeout = const Duration(seconds: 15),
}) {
  final gateway = HttpPersonalTargetMergeSplitPlanGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: identity,
    client: client,
    timeout: timeout,
  );
  addTearDown(gateway.close);
  addTearDown(identity.close);
  return gateway;
}

Future<PersonalTargetMergeSplitPlanResult> _read(
  PersonalTargetMergeSplitPlanGateway gateway, {
  String expectedSubject = _subject,
  bool Function()? current,
}) => gateway.read(
  expectedSubject: expectedSubject,
  workspaceId: _workspaceId,
  projectId: _projectId,
  generationId: _generationId,
  requestIsCurrent: current ?? () => true,
);

PersonalTargetMergeSplitPlan _ready(PersonalTargetMergeSplitPlanResult result) {
  expect(result, isA<PersonalTargetMergeSplitPlanReady>());
  return (result as PersonalTargetMergeSplitPlanReady).plan;
}

void _failure(
  PersonalTargetMergeSplitPlanResult result,
  PersonalTargetMergeSplitPlanFailure failure,
) {
  expect(result, isA<PersonalTargetMergeSplitPlanRejected>());
  expect((result as PersonalTargetMergeSplitPlanRejected).failure, failure);
  expect(result.toString(), isNot(contains('synthetic private')));
}

Future<void> _invalid(_Document wire) async => _failure(
  await _read(_gateway(_Identity(), MockClient((_) async => _response(wire)))),
  PersonalTargetMergeSplitPlanFailure.invalidResponse,
);

const _headers = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};
http.Response _response(
  _Document wire, {
  Map<String, String> headers = _headers,
}) => http.Response.bytes(utf8.encode(jsonEncode(wire)), 200, headers: headers);

_Document _plan(_Document wire) => wire['split_plan'] as _Document;
List<Object?> _facts(_Document wire) => _plan(wire)['facts'] as List<Object?>;
_Document _fact(_Document wire, int index) => _facts(wire)[index] as _Document;
List<Object?> _metadata(_Document wire, int index) =>
    _fact(wire, index)['metadata'] as List<Object?>;

_Document _wire([String type = 'person']) {
  final personId = type == 'person' ? _firstId : _partnerId;
  final institutionId = type == 'institution' ? _firstId : _partnerId;
  return {
    'split_plan': <String, Object?>{
      'generation_id': _generationId,
      'workspace_id': _workspaceId,
      'project_id': _projectId,
      'target_type': type,
      'member_target_ids': <Object?>[_firstId, _secondId],
      'review_due_at_utc': _due,
      'fact_count': 8,
      'fact_fingerprint': _fingerprint,
      'facts': <Object?>[
        {
          'source_target_id': _firstId,
          'metadata': <Object?>[
            'project_revision',
            _firstId,
            _otherProjectId,
            1,
          ],
        },
        {
          'source_target_id': _firstId,
          'metadata': <Object?>['contact_link', _contactId, 1, _firstId],
        },
        {
          'source_target_id': _firstId,
          'metadata': <Object?>[
            'institution_revision_$type',
            _relationshipId,
            1,
            personId,
            institutionId,
            _oldGenerationId,
          ],
        },
        {
          'source_target_id': _firstId,
          'metadata': <Object?>[
            'project_relationship',
            _firstId,
            _otherProjectId,
            4,
            _updatedAt,
          ],
        },
        {
          'source_target_id': _firstId,
          'metadata': <Object?>[
            'institution_relationship_$type',
            _relationshipId,
            personId,
            institutionId,
            2,
            _updatedAt,
            null,
          ],
        },
        {
          'source_target_id': _firstId,
          'metadata': <Object?>['contact_link', _contactId, 3, _firstId],
        },
        {
          'source_target_id': _firstId,
          'metadata': <Object?>[
            'project_revision',
            _firstId,
            _otherProjectId,
            3,
          ],
        },
        {
          'source_target_id': _secondId,
          'metadata': <Object?>['contact_link', '', 1, _secondId],
        },
      ],
    },
  };
}

IdentitySnapshot _snapshot(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: subject, email: null),
);
IdentitySuccess<IdentityAccessToken> _token() => const IdentitySuccess(
  IdentityAccessToken(value: 'synthetic-token', expiresAt: null),
);

final class _Identity implements IdentitySession {
  _Identity({bool synchronous = true})
    : controller = StreamController<IdentitySnapshot>.broadcast(
        sync: synchronous,
      );
  final StreamController<IdentitySnapshot> controller;
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
    if (!controller.isClosed) await controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity operation');
}
