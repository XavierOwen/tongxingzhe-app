import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/personal_target_csv_import.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'preview sends raw CSV bytes with auth and parses exact receipt rows',
    () async {
      final identity = _signedInIdentity();
      final bytes = [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('target_type,display_name,phone,email\nperson,Ada,,'),
      ];
      final gateway = _gateway(identity, (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/promotion-targets/imports/csv/preview');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        expect(request.headers['content-type'], 'text/csv');
        expect(request.bodyBytes, bytes);
        return _response(200, {
          'receipt': _previewReceipt(rowCount: 1),
          'rows': [
            {
              'row_number': 1,
              'target_type': 'person',
              'display_name': 'Ada',
              'phone': null,
              'email': null,
              'hinted': false,
            },
          ],
        });
      });

      final result = await gateway.preview(csvBytes: bytes);
      final preview =
          (result
                  as PersonalTargetCsvImportSuccess<
                    PersonalTargetCsvImportPreview
                  >)
              .value;
      expect(preview.rows.single.type, PromotionTargetType.person);
      expect(preview.rows.single.displayName, 'Ada');
      await gateway.close();
    },
  );

  test(
    'confirm sends all normalized rows in order with actions and request UUID',
    () async {
      final identity = _signedInIdentity();
      var requests = 0;
      final gateway = _gateway(identity, (request) async {
        requests++;
        if (requests == 1) {
          return _response(401, {
            'error': {'code': 'unauthenticated'},
          });
        }
        expect(request.url.path, '/v1/promotion-targets/imports/csv/confirm');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'preview_id': _previewId,
          'request_id': _requestId,
          'rows': [
            {
              'target_type': 'person',
              'display_name': 'Ada',
              'phone': null,
              'email': null,
            },
            {
              'target_type': 'institution',
              'display_name': 'Center',
              'phone': '1',
              'email': null,
            },
          ],
          'actions': ['create', 'skip'],
        });
        return _response(200, {
          'receipt': _confirmReceipt(
            rowCount: 2,
            hintCount: 1,
            createdCount: 1,
            createdTargets: [
              {'row_number': 1, 'target_id': _targetId},
            ],
          ),
        });
      });
      final confirmation = PersonalTargetCsvImportConfirmation(
        previewId: _previewId,
        requestId: _requestId,
        rows: [
          _row(1, hinted: false),
          _row(
            2,
            hinted: true,
            type: PromotionTargetType.institution,
            name: 'Center',
            phone: '1',
          ),
        ],
        actions: [
          PersonalTargetCsvImportAction.create,
          PersonalTargetCsvImportAction.skip,
        ],
      );

      final result = await gateway.confirm(confirmation: confirmation);
      expect(
        result,
        isA<
          PersonalTargetCsvImportSuccess<PersonalTargetCsvImportConfirmReceipt>
        >(),
      );
      expect(identity.accessTokenForceRefreshValues, [false, true]);
      await gateway.close();
    },
  );

  test('401 after token refresh stops after one retry', () async {
    final identity = _signedInIdentity();
    var requests = 0;
    final gateway = _gateway(identity, (_) async {
      requests++;
      return _response(401, {
        'error': {'code': 'unauthenticated'},
      });
    });

    final result = await gateway.preview(csvBytes: [1]);

    expect(
      (result as PersonalTargetCsvImportRejected).code,
      PersonalTargetCsvImportFailureCode.unauthorized,
    );
    expect(requests, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
    await gateway.close();
  });

  test(
    'maps fixed Backend error envelopes to value-free typed failures',
    () async {
      final cases = <int, (String, PersonalTargetCsvImportFailureCode)>{
        400: (
          'invalid_personal_target_csv_import_request',
          PersonalTargetCsvImportFailureCode.invalidInput,
        ),
        401: (
          'unauthenticated',
          PersonalTargetCsvImportFailureCode.unauthorized,
        ),
        403: (
          'personal_target_csv_import_forbidden',
          PersonalTargetCsvImportFailureCode.forbidden,
        ),
        409: (
          'personal_target_csv_import_conflict',
          PersonalTargetCsvImportFailureCode.conflict,
        ),
        413: (
          'payload_too_large',
          PersonalTargetCsvImportFailureCode.payloadTooLarge,
        ),
        415: (
          'unsupported_personal_target_csv_import_media_type',
          PersonalTargetCsvImportFailureCode.unsupportedMediaType,
        ),
        503: (
          'personal_target_csv_import_unavailable',
          PersonalTargetCsvImportFailureCode.serviceUnavailable,
        ),
      };
      for (final entry in cases.entries) {
        final gateway = _gateway(
          _signedInIdentity(),
          (_) async => _response(entry.key, {
            'error': {'code': entry.value.$1},
          }),
        );
        final result = await gateway.preview(csvBytes: [1]);
        expect(
          (result as PersonalTargetCsvImportRejected).code,
          entry.value.$2,
        );
        await gateway.close();
      }
      final gateway = _gateway(
        _signedInIdentity(),
        (_) async => _response(422, {
          'error': {
            'code': 'invalid_personal_target_csv_import_rows',
            'issues': [
              {
                'row_number': 1,
                'field': 'display_name',
                'code': 'invalid_length',
              },
            ],
          },
        }),
      );
      final invalid = await gateway.preview(csvBytes: [1]);
      final rejected = invalid as PersonalTargetCsvImportRejected;
      expect(rejected.code, PersonalTargetCsvImportFailureCode.invalidRows);
      expect(rejected.issues.single.field, 'display_name');
      await gateway.close();

      final arbitraryIssue = _gateway(
        _signedInIdentity(),
        (_) async => _response(422, {
          'error': {
            'code': 'invalid_personal_target_csv_import_rows',
            'issues': [
              {
                'row_number': 1,
                'field': 'private value',
                'code': 'private value',
              },
            ],
          },
        }),
      );
      expect(
        (await arbitraryIssue.preview(csvBytes: [1])
                as PersonalTargetCsvImportRejected)
            .code,
        PersonalTargetCsvImportFailureCode.malformedResponse,
      );
      await arbitraryIssue.close();
    },
  );

  test('malformed or extra response fields fail closed', () async {
    for (final body in [
      {'receipt': _previewReceipt(rowCount: 0), 'rows': [], 'extra': true},
      {
        'receipt': {..._previewReceipt(rowCount: 0), 'extra': true},
        'rows': [],
      },
      {
        'receipt': _previewReceipt(rowCount: 1),
        'rows': [
          {
            'row_number': 1,
            'target_type': 'person',
            'display_name': ' Ada ',
            'phone': null,
            'email': null,
            'hinted': false,
          },
        ],
      },
      {
        'receipt': _previewReceipt(rowCount: 1),
        'rows': [
          {
            'row_number': 1,
            'target_type': 'person',
            'display_name': List.filled(201, 'x').join(),
            'phone': null,
            'email': null,
            'hinted': false,
          },
        ],
      },
    ]) {
      final gateway = _gateway(
        _signedInIdentity(),
        (_) async => _response(200, body),
      );
      final result = await gateway.preview(csvBytes: [1]);
      expect(
        (result as PersonalTargetCsvImportRejected).code,
        PersonalTargetCsvImportFailureCode.malformedResponse,
      );
      await gateway.close();
    }

    final confirmation = PersonalTargetCsvImportConfirmation(
      previewId: _previewId,
      requestId: _requestId,
      rows: [_row(1)],
      actions: [PersonalTargetCsvImportAction.create],
    );
    final staleOnSuccess = _gateway(
      _signedInIdentity(),
      (_) async => _response(200, {
        'receipt': _confirmReceipt(
          rowCount: 1,
          hintCount: 0,
          createdCount: 0,
          outcome: 'stale_preview',
          createdTargets: [],
        ),
      }),
    );
    expect(
      (await staleOnSuccess.confirm(confirmation: confirmation)
              as PersonalTargetCsvImportRejected)
          .code,
      PersonalTargetCsvImportFailureCode.malformedResponse,
    );
    await staleOnSuccess.close();
  });

  test(
    'accepts millisecond UTC timestamps and rejects offset timestamps',
    () async {
      final validGateway = _gateway(
        _signedInIdentity(),
        (_) async => _response(200, {
          'receipt': _previewReceipt(rowCount: 0, milliseconds: true),
          'rows': [],
        }),
      );
      expect(
        await validGateway.preview(csvBytes: [1]),
        isA<PersonalTargetCsvImportSuccess<PersonalTargetCsvImportPreview>>(),
      );
      await validGateway.close();

      final invalid = _previewReceipt(rowCount: 0, milliseconds: true)
        ..['previewed_at_utc'] = '2026-10-08T10:00:00.000+00:00';
      final invalidGateway = _gateway(
        _signedInIdentity(),
        (_) async => _response(200, {'receipt': invalid, 'rows': []}),
      );
      expect(
        (await invalidGateway.preview(csvBytes: [1])
                as PersonalTargetCsvImportRejected)
            .code,
        PersonalTargetCsvImportFailureCode.malformedResponse,
      );
      await invalidGateway.close();
    },
  );

  test('409 stale receipt is distinct from conflict', () async {
    final confirmation = PersonalTargetCsvImportConfirmation(
      previewId: _previewId,
      requestId: _requestId,
      rows: [_row(1)],
      actions: [PersonalTargetCsvImportAction.create],
    );
    final gateway = _gateway(
      _signedInIdentity(),
      (_) async => _response(409, {
        'receipt': _confirmReceipt(
          rowCount: 1,
          hintCount: 0,
          createdCount: 0,
          outcome: 'stale_preview',
          createdTargets: [],
        ),
      }),
    );
    expect(
      await gateway.confirm(confirmation: confirmation),
      isA<PersonalTargetCsvImportStale>(),
    );
    await gateway.close();
  });

  test('network exceptions map to a value-free network failure', () async {
    final gateway = _gateway(
      _signedInIdentity(),
      (_) async => throw http.ClientException('private response details'),
    );
    final result = await gateway.preview(csvBytes: [1]);
    expect(
      (result as PersonalTargetCsvImportRejected).code,
      PersonalTargetCsvImportFailureCode.networkUnavailable,
    );
    await gateway.close();
  });
}

HttpPersonalTargetCsvImportGateway _gateway(
  FakeIdentitySession identity,
  Future<http.Response> Function(http.Request) handler,
) => HttpPersonalTargetCsvImportGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity,
  client: MockClient(handler),
);

http.Response _response(int status, Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _previewReceipt({
  required int rowCount,
  bool milliseconds = false,
}) => {
  'contract_id': 'personal-target-csv-import-preview:v1',
  'preview_id': _previewId,
  'row_count': rowCount,
  'hinted_rows': <int>[],
  'previewed_at_utc': milliseconds
      ? '2026-10-08T10:00:00.000Z'
      : '2026-10-08T10:00:00.000000Z',
  'expires_at_utc': milliseconds
      ? '2026-10-08T10:15:00.000Z'
      : '2026-10-08T10:15:00.000000Z',
};

Map<String, Object?> _confirmReceipt({
  required int rowCount,
  required int hintCount,
  required int createdCount,
  String outcome = 'confirmed',
  required List<Map<String, Object?>> createdTargets,
}) => {
  'contract_id': 'personal-target-csv-import-confirm:v1',
  'preview_id': _previewId,
  'request_id': _requestId,
  'outcome': outcome,
  'row_count': rowCount,
  'hint_count': hintCount,
  'created_count': createdCount,
  'created_targets': createdTargets,
  'completed_at_utc': '2026-10-08T10:01:00.000000Z',
};

PersonalTargetCsvImportPreviewRow _row(
  int number, {
  bool hinted = false,
  PromotionTargetType type = PromotionTargetType.person,
  String name = 'Ada',
  String? phone,
}) => PersonalTargetCsvImportPreviewRow(
  rowNumber: number,
  type: type,
  displayName: name,
  phone: phone,
  email: null,
  hinted: hinted,
);

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'test-subject',
      email: 'test@example.test',
    ),
  ),
);

const _previewId = '22222222-2222-4222-8222-222222222222';
const _requestId = '33333333-3333-4333-8333-333333333333';
const _targetId = '44444444-4444-4444-8444-444444444444';
