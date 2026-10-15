import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/http_personal_target_merge_directory_gateway.dart';
import 'package:tongxingzhe_app/targets/personal_target_merge_directory.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

const _subject = ' owner ';
const _workspaceId = '7ee00000-0000-4000-8000-000000000001';
const _projectId = '7ee00000-0000-4000-8000-000000000002';
const _generationId = '7ee00000-0000-4000-8000-000000000003';
const _firstId = '7ee00000-0000-4000-8000-000000000011';
const _secondId = '7ee00000-0000-4000-8000-000000000012';
const _partnerId = '7ee00000-0000-4000-8000-000000000013';
const _due = '2027-10-15T12:34:56.123455Z';
typedef _Document = Map<String, Object?>;

void main() {
  test(
    'accepts nil and max PostgreSQL UUID cursor and result boundaries',
    () async {
      const nil = '00000000-0000-0000-0000-000000000000';
      const max = 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF';
      for (final (after, generationId) in <(String?, String?)>[
        (null, nil),
        (nil, max),
        (max, null),
      ]) {
        final wire = _wire(count: generationId == null ? 0 : 1);
        if (generationId != null) {
          _item(wire)['generation_id'] = generationId;
          _item(wire)['member_target_ids'] = [nil, max];
          _item(wire)['retained_target_id'] = max;
        }
        final gateway = _gateway(
          _Identity(),
          MockClient((request) async {
            expect(
              request.url.queryParameters,
              after == null ? <String, String>{} : {'after': after},
            );
            return _response(wire);
          }),
        );
        final directory = _ready(
          await _read(gateway, afterGenerationId: after),
        );
        expect(directory.items, hasLength(generationId == null ? 0 : 1));
        if (generationId != null) {
          expect(directory.items.single.generationId, generationId);
          expect(directory.items.single.memberTargetIds, [nil, max]);
        }
      }
    },
  );
  test('uses only the directory GET and optional after query', () async {
    for (final after in [null, _generationId]) {
      final gateway = _gateway(
        _Identity(),
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/v1/projects/$_projectId/promotion-target-merges',
          );
          expect(
            request.url.queryParameters,
            after == null ? <String, String>{} : {'after': after},
          );
          expect(request.body, isEmpty);
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          expect(request.headers['accept'], 'application/json');
          return _response(_wire(count: 20, next: true));
        }),
      );
      final directory = _ready(await _read(gateway, afterGenerationId: after));
      expect(directory.workspaceId, _workspaceId);
      expect(directory.projectId, _projectId);
      expect(directory.items, hasLength(personalTargetMergeDirectoryPageSize));
      expect(directory.nextCursor, _id(119));
      expect(directory.items.first.generationId, _id(100));
      expect(directory.items.first.memberTargetIds, [_firstId, _secondId]);
      expect(directory.items.first.retainedTargetId, _secondId);
      expect(directory.items.first.reviewDueAtUtc.microsecond, 455);
      expect(directory.items.first.targetType, PromotionTargetType.person);
      expect(directory.items[1].targetType, PromotionTargetType.institution);
    }
  });
  test(
    'accepts empty and terminal full pages with arbitrary UUID boundaries',
    () async {
      for (final count in [0, 1, 20]) {
        final directory = _ready(
          await _read(
            _gateway(
              _Identity(),
              MockClient((_) async => _response(_wire(count: count))),
            ),
            afterGenerationId: _generationId,
          ),
        );
        expect(directory.items, hasLength(count));
        expect(directory.nextCursor, isNull);
      }
    },
  );
  test(
    'preserves UUID spelling and accepts an older due without a client clock gate',
    () async {
      final wire = _wire();
      _directory(wire)['workspace_id'] = _workspaceId.toUpperCase();
      _item(wire)['generation_id'] = _id(100).toUpperCase();
      _item(wire)['retained_target_id'] = _secondId.toUpperCase();
      _item(wire)['member_target_ids'] = [_firstId.toUpperCase(), _secondId];
      _item(wire)['review_due_at_utc'] = '2020-01-01T00:00:00.000000Z';
      final directory = _ready(
        await _read(
          _gateway(_Identity(), MockClient((_) async => _response(wire))),
        ),
      );
      expect(directory.workspaceId, _workspaceId.toUpperCase());
      expect(directory.items.first.generationId, _id(100).toUpperCase());
      expect(directory.items.first.retainedTargetId, _secondId.toUpperCase());
      expect(
        directory.items.first.memberTargetIds.first,
        _firstId.toUpperCase(),
      );
      expect(directory.items.first.reviewDueAtUtc, DateTime.utc(2020));
    },
  );
  test('copies constructor lists and exposes no mutable nested lists', () {
    final members = <String>[_firstId, _secondId];
    final item = PersonalTargetMergeDirectoryItem(
      generationId: _generationId,
      targetType: PromotionTargetType.person,
      retainedTargetId: _firstId,
      memberTargetIds: members,
      reviewDueAtUtc: DateTime.parse(_due),
    );
    final items = <PersonalTargetMergeDirectoryItem>[item];
    final directory = PersonalTargetMergeDirectory(
      workspaceId: _workspaceId,
      projectId: _projectId,
      items: items,
      nextCursor: null,
    );
    members.clear();
    items.clear();
    expect(directory.items, hasLength(1));
    expect(item.memberTargetIds, hasLength(2));
    expect(() => directory.items.clear(), throwsUnsupportedError);
    expect(() => item.memberTargetIds.clear(), throwsUnsupportedError);
  });
  test(
    'requires exact root, no-store JSON UTF-8 and valid JSON bytes',
    () async {
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
          PersonalTargetMergeDirectoryFailure.invalidResponse,
        );
      }
      for (final bytes in [
        <int>[255],
        utf8.encode('{'),
        utf8.encode('[]'),
        utf8.encode('{"directory":null}'),
        utf8.encode(jsonEncode({..._wire(), 'extra': true})),
        utf8.encode(jsonEncode({'projection': _directory(_wire())})),
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
          PersonalTargetMergeDirectoryFailure.invalidResponse,
        );
      }
    },
  );
  for (final (name, layer, keys)
      in <(String, _Document Function(_Document), List<String>)>[
        (
          'directory',
          _directory,
          ['workspace_id', 'project_id', 'items', 'next_cursor'],
        ),
        (
          'item',
          _item,
          [
            'generation_id',
            'target_type',
            'retained_target_id',
            'member_target_ids',
            'review_due_at_utc',
          ],
        ),
      ]) {
    for (final key in keys) {
      test('rejects missing $name key $key', () async {
        final wire = _wire();
        layer(wire).remove(key);
        await _invalid(wire);
      });
    }
  }
  final mutations = <(String, void Function(_Document))>[
    ('workspace scope', (w) => _directory(w)['workspace_id'] = _partnerId),
    ('project scope', (w) => _directory(w)['project_id'] = _partnerId),
    (
      'extra directory profile',
      (w) => _directory(w)['display_name'] = 'private',
    ),
    ('item list', (w) => _directory(w)['items'] = {}),
    (
      'too many items',
      (w) => _directory(w)['items'] = _directory(_wire(count: 21))['items'],
    ),
    ('item object', (w) => _directory(w)['items'] = <Object?>[[]]),
    ('extra item profile', (w) => _item(w)['phone'] = 'private'),
    ('generation UUID', (w) => _item(w)['generation_id'] = 'generation'),
    ('UUID newline', (w) => _item(w)['generation_id'] = '${_id(100)}\n'),
    ('target type', (w) => _item(w)['target_type'] = 'organization'),
    (
      'retained outside pair',
      (w) => _item(w)['retained_target_id'] = _partnerId,
    ),
    ('member list', (w) => _item(w)['member_target_ids'] = {}),
    ('member count', (w) => _item(w)['member_target_ids'] = [_firstId]),
    ('member UUID', (w) => _item(w)['member_target_ids'] = ['bad', _secondId]),
    (
      'member order',
      (w) => _item(w)['member_target_ids'] = [_secondId, _firstId],
    ),
    (
      'member duplicate',
      (w) => _item(w)['member_target_ids'] = [_firstId, _firstId.toUpperCase()],
    ),
    ('short page next cursor', (w) => _directory(w)['next_cursor'] = _id(100)),
    ('cursor UUID', (w) => _directory(w)['next_cursor'] = 'bad'),
  ];
  for (final (name, mutate) in mutations) {
    test('rejects $name', () async {
      final wire = _wire();
      mutate(wire);
      await _invalid(wire);
    });
  }
  test(
    'rejects unsorted, duplicate or boundary-crossing generations and inconsistent next cursors',
    () async {
      for (final ids in [
        [_id(101), _id(100)],
        [_id(100), _id(100).toUpperCase()],
      ]) {
        final wire = _wire(count: 2);
        for (var i = 0; i < 2; i++) {
          (_directory(wire)['items'] as List<_Document>)[i]['generation_id'] =
              ids[i];
        }
        await _invalid(wire);
      }
      for (final after in [_id(100), _id(101)]) {
        await _invalid(_wire(), afterGenerationId: after);
      }
      final wire = _wire(count: 20, next: true);
      _directory(wire)['next_cursor'] = _id(118);
      await _invalid(wire);
      final empty = _wire(count: 0);
      _directory(empty)['next_cursor'] = _id(100);
      await _invalid(empty);
      final full = _wire(count: 20, next: true);
      _directory(full)['next_cursor'] = _id(119).toUpperCase();
      expect(
        _ready(
          await _read(
            _gateway(_Identity(), MockClient((_) async => _response(full))),
          ),
        ).nextCursor,
        _id(119).toUpperCase(),
      );
    },
  );
  test(
    'rejects noncanonical or impossible six-microsecond UTC dates',
    () async {
      for (final time in [
        null,
        1,
        '0000-01-01T00:00:00.000000Z',
        '2026-02-30T12:00:00.000000Z',
        '2026-01-01T24:00:00.000000Z',
        '2026-01-01T00:00:60.000000Z',
        '2026-01-01T00:00:00Z',
        '2026-01-01T00:00:00.123Z',
        '2026-01-01T00:00:00.1234567Z',
        '2026-01-01T00:00:00.000000+00:00',
        '2026-01-01T00:00:00.000000Z\n',
      ]) {
        final wire = _wire();
        _item(wire)['review_due_at_utc'] = time;
        await _invalid(wire);
      }
    },
  );
  test(
    'maps statuses without private body values and refreshes 401 only once',
    () async {
      for (final (status, failure) in [
        (400, PersonalTargetMergeDirectoryFailure.invalidRequest),
        (401, PersonalTargetMergeDirectoryFailure.unauthenticated),
        (403, PersonalTargetMergeDirectoryFailure.forbidden),
        (503, PersonalTargetMergeDirectoryFailure.serviceUnavailable),
        (500, PersonalTargetMergeDirectoryFailure.invalidResponse),
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
      expect(result, isA<PersonalTargetMergeDirectoryReady>());
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
        PersonalTargetMergeDirectoryFailure.unauthenticated,
      );
      _failure(
        await _read(gateway, current: () => false),
        PersonalTargetMergeDirectoryFailure.requestInvalidated,
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
            afterGenerationId: scope.$3,
            requestIsCurrent: () => true,
          ),
          PersonalTargetMergeDirectoryFailure.invalidRequest,
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
              ? PersonalTargetMergeDirectoryFailure.networkUnavailable
              : PersonalTargetMergeDirectoryFailure.unauthenticated,
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
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
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
          PersonalTargetMergeDirectoryFailure.networkUnavailable,
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
              PersonalTargetMergeDirectoryFailure.requestInvalidated,
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
      isA<PersonalTargetMergeDirectoryReady>(),
    );
    firstResponse.complete(_response(_wire()));
    _failure(await old, PersonalTargetMergeDirectoryFailure.requestInvalidated);
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
      PersonalTargetMergeDirectoryFailure.requestInvalidated,
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
      expect(await _read(gateway), isA<PersonalTargetMergeDirectoryReady>());
      await gateway.close();
      await gateway.close();
      _failure(
        await _read(gateway),
        PersonalTargetMergeDirectoryFailure.requestInvalidated,
      );
      expect(requests, 1);
      expect(identity.closed, isFalse);
    },
  );

  test(
    'validates the Backend URI and provides an unavailable deferred gateway',
    () async {
      expect(
        () => HttpPersonalTargetMergeDirectoryGateway(
          baseUri: Uri.parse('http://remote.example.test'),
          identitySession: _Identity(),
          client: MockClient((_) async => _response(_wire())),
        ),
        throwsFormatException,
      );
      const gateway = DeferredPersonalTargetMergeDirectoryGateway();
      _failure(
        await _read(gateway),
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
      );
      await gateway.close();
    },
  );
}

HttpPersonalTargetMergeDirectoryGateway _gateway(
  _Identity identity,
  http.Client client, {
  Duration timeout = const Duration(seconds: 15),
}) {
  final gateway = HttpPersonalTargetMergeDirectoryGateway(
    baseUri: Uri.parse('https://backend.example.test'),
    identitySession: identity,
    client: client,
    timeout: timeout,
  );
  addTearDown(gateway.close);
  addTearDown(identity.close);
  return gateway;
}

Future<PersonalTargetMergeDirectoryResult> _read(
  PersonalTargetMergeDirectoryGateway gateway, {
  String expectedSubject = _subject,
  bool Function()? current,
  String? afterGenerationId,
}) => gateway.read(
  expectedSubject: expectedSubject,
  workspaceId: _workspaceId,
  projectId: _projectId,
  afterGenerationId: afterGenerationId,
  requestIsCurrent: current ?? () => true,
);

PersonalTargetMergeDirectory _ready(PersonalTargetMergeDirectoryResult result) {
  expect(result, isA<PersonalTargetMergeDirectoryReady>());
  return (result as PersonalTargetMergeDirectoryReady).directory;
}

void _failure(
  PersonalTargetMergeDirectoryResult result,
  PersonalTargetMergeDirectoryFailure failure,
) {
  expect(result, isA<PersonalTargetMergeDirectoryRejected>());
  expect((result as PersonalTargetMergeDirectoryRejected).failure, failure);
  expect(result.toString(), isNot(contains('synthetic private')));
}

Future<void> _invalid(_Document wire, {String? afterGenerationId}) async =>
    _failure(
      await _read(
        _gateway(_Identity(), MockClient((_) async => _response(wire))),
        afterGenerationId: afterGenerationId,
      ),
      PersonalTargetMergeDirectoryFailure.invalidResponse,
    );
const _headers = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};
http.Response _response(
  _Document wire, {
  Map<String, String> headers = _headers,
}) => http.Response.bytes(utf8.encode(jsonEncode(wire)), 200, headers: headers);
_Document _directory(_Document wire) => wire['directory'] as _Document;
_Document _item(_Document wire) =>
    (_directory(wire)['items'] as List<_Document>).first;
String _id(int value) =>
    '7ee00000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
_Document _wire({int count = 1, bool next = false}) => {
  'directory': <String, Object?>{
    'workspace_id': _workspaceId,
    'project_id': _projectId,
    'next_cursor': next ? _id(100 + count - 1) : null,
    'items': <_Document>[
      for (var i = 0; i < count; i++)
        {
          'generation_id': _id(100 + i),
          'target_type': i.isEven ? 'person' : 'institution',
          'retained_target_id': _secondId,
          'member_target_ids': <Object?>[_firstId, _secondId],
          'review_due_at_utc': _due,
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
