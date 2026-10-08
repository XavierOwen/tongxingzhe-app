import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/personal_pii_export_gateway.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'sends one fixed GET with current token and preserves original bytes',
    () async {
      final identity = _signedInIdentity();
      final bytes = _validBytes();
      final gateway = _gateway(
        identity,
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/promotion-targets/export');
          expect(request.url.query, isEmpty);
          expect(request.body, isEmpty);
          expect(request.headers['accept'], 'application/json');
          expect(
            request.headers['authorization'],
            'Bearer test-only-access-token',
          );
          expect(request.headers.containsKey('content-type'), isFalse);
          return _response(bytes);
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.export(requestIsCurrent: () => true);
      final artifact = _artifact(result);
      expect(artifact.bytes, orderedEquals(bytes));
      expect(artifact.fileName, 'personal-promotion-target-pii-v1.json');
      expect(artifact.contentType, 'application/json; charset=utf-8');
      expect(() => artifact.bytes.add(0), throwsUnsupportedError);
      expect(identity.accessTokenForceRefreshValues, [false]);
    },
  );

  test(
    'maps auth, forbidden, service, and network failures without body data',
    () async {
      for (final entry in <(http.Response, PersonalPiiExportFailure)>[
        (
          http.Response('private phone 555-0100', 401),
          PersonalPiiExportFailure.unauthenticated,
        ),
        (
          http.Response(
            '{"error":{"code":"reauthentication_required"},"name":"private"}',
            403,
          ),
          PersonalPiiExportFailure.reauthenticationRequired,
        ),
        (
          http.Response('{"code":"personal_target_pii_export_forbidden"}', 403),
          PersonalPiiExportFailure.exportForbidden,
        ),
        (
          http.Response('private email', 503),
          PersonalPiiExportFailure.serviceUnavailable,
        ),
      ]) {
        final gateway = _gateway(
          _signedInIdentity(),
          MockClient((_) async => entry.$1),
        );
        addTearDown(gateway.close);
        final result = await gateway.export(requestIsCurrent: () => true);
        expect(result, isA<PersonalPiiExportRejected>());
        expect((result as PersonalPiiExportRejected).failure, entry.$2);
        expect(result.toString(), isNot(contains('private')));
      }

      final network = _gateway(
        _signedInIdentity(),
        MockClient((_) async => throw http.ClientException('sensitive detail')),
      );
      addTearDown(network.close);
      expect(
        (await network.export(requestIsCurrent: () => true)
                as PersonalPiiExportRejected)
            .failure,
        PersonalPiiExportFailure.networkUnavailable,
      );

      final timeout = HttpPersonalPiiExportGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 5),
      );
      addTearDown(timeout.close);
      expect(
        (await timeout.export(requestIsCurrent: () => true)
                as PersonalPiiExportRejected)
            .failure,
        PersonalPiiExportFailure.networkUnavailable,
      );
    },
  );

  test(
    'does not send after an account ABA while access token is pending',
    () async {
      final identity = _signedInIdentity();
      final tokenRequested = Completer<void>();
      final releaseToken = Completer<void>();
      identity
        ..accessTokenRequested = tokenRequested
        ..accessTokenBarrier = releaseToken.future;
      var requests = 0;
      final gateway = _gateway(
        identity,
        MockClient((_) async {
          requests++;
          return _response(_validBytes());
        }),
      );
      addTearDown(gateway.close);

      final export = gateway.export(requestIsCurrent: () => true);
      await tokenRequested.future;
      identity.emit(_identitySnapshot('other-subject'));
      identity.emit(_identitySnapshot('external-subject'));
      await Future<void>.delayed(Duration.zero);
      releaseToken.complete();

      expect(
        (await export as PersonalPiiExportRejected).failure,
        PersonalPiiExportFailure.unauthenticated,
      );
      expect(requests, 0);
    },
  );

  test('does not send after the page request fence is broken', () async {
    final identity = _signedInIdentity();
    final tokenRequested = Completer<void>();
    final releaseToken = Completer<void>();
    identity
      ..accessTokenRequested = tokenRequested
      ..accessTokenBarrier = releaseToken.future;
    var requestIsCurrent = true;
    var requests = 0;
    final gateway = _gateway(
      identity,
      MockClient((_) async {
        requests++;
        return _response(_validBytes());
      }),
    );
    addTearDown(gateway.close);

    final export = gateway.export(requestIsCurrent: () => requestIsCurrent);
    await tokenRequested.future;
    requestIsCurrent = false;
    releaseToken.complete();

    expect(
      (await export as PersonalPiiExportRejected).failure,
      PersonalPiiExportFailure.unauthenticated,
    );
    expect(requests, 0);
  });

  test(
    'rejects response header drift, malformed JSON, and schema drift',
    () async {
      final goodBytes = _validBytes();
      final badHeaders = <Map<String, String>>[
        _headers(goodBytes)
          ..['content-type'] = 'application/json; charset=utf-16',
        _headers(goodBytes)
          ..['content-type'] = 'Application/JSON; charset=UTF-8',
        _headers(goodBytes)
          ..['content-disposition'] = 'attachment; filename="other.json"',
        _headers(goodBytes)
          ..['content-disposition'] =
              'attachment ; filename = "personal-promotion-target-pii-v1.json"',
        _headers(goodBytes)
          ..['content-disposition'] =
              'attachment; filename="PERSONAL-promotion-target-pii-v1.json"',
        _headers(goodBytes)..['cache-control'] = 'private',
        _headers(goodBytes)..['x-content-type-options'] = 'sniff',
        _headers(goodBytes)..['content-length'] = '${goodBytes.length + 1}',
      ];
      for (final headers in badHeaders) {
        expect(
          await _export(_response(goodBytes, headers: headers)),
          isA<PersonalPiiExportRejected>(),
        );
      }

      final malformed = <List<int>>[
        utf8.encode('{'),
        [0xff, 0xfe],
        utf8.encode(_json({'export_contract_id': 'wrong'})),
        utf8.encode(_json(_document()..['extra'] = true)),
        utf8.encode(
          _json({
            'export_event_id': _document()['export_event_id'],
            'export_contract_id': _document()['export_contract_id'],
            'exported_at_utc': _document()['exported_at_utc'],
            'targets': _document()['targets'],
          }),
        ),
        utf8.encode(_json(_document()..['export_event_id'] = 'not-a-uuid')),
        utf8.encode(
          _json(_document()..['exported_at_utc'] = '2030-01-02T03:04:05Z'),
        ),
        utf8.encode(
          _json(_document()..['targets'] = [_target()..['email'] = 3]),
        ),
        utf8.encode(
          _json(_document()..['targets'] = [_target()..['extra'] = 'x']),
        ),
        utf8.encode(
          _json(
            _document()
              ..['targets'] = [
                {
                  'display_name': 'Private Name',
                  'target_type': 'person',
                  'phone': '+15550100000',
                  'email': 'private@example.test',
                },
              ],
          ),
        ),
        utf8.encode(
          _json(_document()..['targets'] = [_target()..['phone'] = false]),
        ),
        utf8.encode(
          _json(
            _document()..['targets'] = [_target()..['target_type'] = 'other'],
          ),
        ),
      ];
      for (final bytes in malformed) {
        expect(
          await _export(_response(bytes)),
          isA<PersonalPiiExportRejected>(),
        );
      }
      expect(
        await _export(_response(goodBytes.sublist(0, goodBytes.length - 1))),
        isA<PersonalPiiExportRejected>(),
      );
    },
  );
}

Future<PersonalPiiExportResult> _export(http.Response response) async {
  final gateway = _gateway(
    _signedInIdentity(),
    MockClient((_) async => response),
  );
  try {
    return await gateway.export(requestIsCurrent: () => true);
  } finally {
    await gateway.close();
  }
}

HttpPersonalPiiExportGateway _gateway(
  IdentitySession identity,
  http.Client client,
) => HttpPersonalPiiExportGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity,
  client: client,
);

PersonalPiiExportArtifact _artifact(PersonalPiiExportResult result) {
  expect(result, isA<PersonalPiiExportReady>());
  return (result as PersonalPiiExportReady).artifact;
}

FakeIdentitySession _signedInIdentity() =>
    FakeIdentitySession(initial: _identitySnapshot('external-subject'));

IdentitySnapshot _identitySnapshot(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: 'owner@example.test',
  ),
);

http.Response _response(List<int> bytes, {Map<String, String>? headers}) =>
    http.Response.bytes(bytes, 200, headers: headers ?? _headers(bytes));

Map<String, String> _headers(List<int> bytes) => {
  'content-type': 'application/json; charset=utf-8',
  'content-disposition':
      'attachment; filename="personal-promotion-target-pii-v1.json"',
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
  'content-length': '${bytes.length}',
};

List<int> _validBytes() => utf8.encode(_json(_document()));

Map<String, Object?> _document() => {
  'export_contract_id': 'personal_promotion_target_pii_export_v1',
  'export_event_id': 'a718b5a2-83a4-4a2f-8f66-087382fa8291',
  'exported_at_utc': '2030-01-02T03:04:05.006Z',
  'targets': [_target(), _nullableTarget()],
};

Map<String, Object?> _target() => {
  'target_type': 'person',
  'display_name': 'Private Name',
  'phone': '+15550100000',
  'email': 'private@example.test',
};

Map<String, Object?> _nullableTarget() => {
  'target_type': 'institution',
  'display_name': 'Private Institution',
  'phone': null,
  'email': null,
};

String _json(Object? value) => jsonEncode(value);
