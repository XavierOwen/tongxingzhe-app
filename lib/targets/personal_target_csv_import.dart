import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'promotion_target.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _previewContract = 'personal-target-csv-import-preview:v1';
const _confirmContract = 'personal-target-csv-import-confirm:v1';
const personalTargetCsvImportMaxFileBytes = 1024 * 1024;

PersonalTargetCsvImportGateway productionPersonalTargetCsvImportGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalTargetCsvImportGateway();
  }
  return HttpPersonalTargetCsvImportGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

enum PersonalTargetCsvImportFailureCode {
  unauthorized,
  forbidden,
  invalidInput,
  conflict,
  payloadTooLarge,
  unsupportedMediaType,
  invalidRows,
  serviceUnavailable,
  networkUnavailable,
  malformedResponse,
}

sealed class PersonalTargetCsvImportResult<T> {
  const PersonalTargetCsvImportResult();
}

final class PersonalTargetCsvImportSuccess<T>
    extends PersonalTargetCsvImportResult<T> {
  const PersonalTargetCsvImportSuccess(this.value);

  final T value;
}

final class PersonalTargetCsvImportRejected<T>
    extends PersonalTargetCsvImportResult<T> {
  const PersonalTargetCsvImportRejected(this.code, {this.issues = const []});

  final PersonalTargetCsvImportFailureCode code;
  final List<PersonalTargetCsvImportIssue> issues;
}

final class PersonalTargetCsvImportStale<T>
    extends PersonalTargetCsvImportResult<T> {
  const PersonalTargetCsvImportStale(this.receipt);

  final PersonalTargetCsvImportConfirmReceipt receipt;
}

final class PersonalTargetCsvImportIssue {
  const PersonalTargetCsvImportIssue({
    required this.rowNumber,
    required this.field,
    required this.code,
  });

  final int rowNumber;
  final String field;
  final String code;
}

final class PersonalTargetCsvImportPreviewReceipt {
  const PersonalTargetCsvImportPreviewReceipt({
    required this.previewId,
    required this.rowCount,
    required this.hintedRows,
    required this.previewedAtUtc,
    required this.expiresAtUtc,
  });

  final String previewId;
  final int rowCount;
  final List<int> hintedRows;
  final DateTime previewedAtUtc;
  final DateTime expiresAtUtc;
}

final class PersonalTargetCsvImportPreviewRow {
  const PersonalTargetCsvImportPreviewRow({
    required this.rowNumber,
    required this.type,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.hinted,
  });

  final int rowNumber;
  final PromotionTargetType type;
  final String displayName;
  final String? phone;
  final String? email;
  final bool hinted;
}

final class PersonalTargetCsvImportPreview {
  const PersonalTargetCsvImportPreview({
    required this.receipt,
    required this.rows,
  });

  final PersonalTargetCsvImportPreviewReceipt receipt;
  final List<PersonalTargetCsvImportPreviewRow> rows;
}

enum PersonalTargetCsvImportAction {
  skip('skip'),
  create('create'),
  createSeparate('create_separate');

  const PersonalTargetCsvImportAction(this.storageValue);

  final String storageValue;
}

final class PersonalTargetCsvImportConfirmation {
  const PersonalTargetCsvImportConfirmation({
    required this.previewId,
    required this.requestId,
    required this.rows,
    required this.actions,
  });

  final String previewId;
  final String requestId;
  final List<PersonalTargetCsvImportPreviewRow> rows;
  final List<PersonalTargetCsvImportAction> actions;
}

final class PersonalTargetCsvImportCreatedTarget {
  const PersonalTargetCsvImportCreatedTarget({
    required this.rowNumber,
    required this.targetId,
  });

  final int rowNumber;
  final String targetId;
}

final class PersonalTargetCsvImportConfirmReceipt {
  const PersonalTargetCsvImportConfirmReceipt({
    required this.previewId,
    required this.requestId,
    required this.stale,
    required this.rowCount,
    required this.hintCount,
    required this.createdCount,
    required this.createdTargets,
    required this.completedAtUtc,
  });

  final String previewId;
  final String requestId;
  final bool stale;
  final int rowCount;
  final int hintCount;
  final int createdCount;
  final List<PersonalTargetCsvImportCreatedTarget> createdTargets;
  final DateTime completedAtUtc;
}

abstract interface class PersonalTargetCsvImportGateway {
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportPreview>>
  preview({required List<int> csvBytes});

  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportConfirmReceipt>>
  confirm({required PersonalTargetCsvImportConfirmation confirmation});

  Future<void> close();
}

final class DeferredPersonalTargetCsvImportGateway
    implements PersonalTargetCsvImportGateway {
  const DeferredPersonalTargetCsvImportGateway();

  @override
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportPreview>>
  preview({required List<int> csvBytes}) async =>
      const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.networkUnavailable,
      );

  @override
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportConfirmReceipt>>
  confirm({required PersonalTargetCsvImportConfirmation confirmation}) async =>
      const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.networkUnavailable,
      );

  @override
  Future<void> close() async {}
}

final class HttpPersonalTargetCsvImportGateway
    implements PersonalTargetCsvImportGateway {
  factory HttpPersonalTargetCsvImportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalTargetCsvImportGateway._(
    validateBackendBaseUri(baseUri),
    identitySession,
    client,
    timeout,
  );

  HttpPersonalTargetCsvImportGateway._(
    this._baseUri,
    this._identitySession,
    this._client,
    this._timeout,
  );

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportPreview>>
  preview({required List<int> csvBytes}) async {
    if (csvBytes.length > personalTargetCsvImportMaxFileBytes) {
      return const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.payloadTooLarge,
      );
    }
    final response = await _request(
      method: 'POST',
      path: '/v1/promotion-targets/imports/csv/preview',
      contentType: 'text/csv',
      bytes: csvBytes,
    );
    if (response is PersonalTargetCsvImportRejected<http.Response>) {
      return PersonalTargetCsvImportRejected(
        response.code,
        issues: response.issues,
      );
    }
    return _parseResult(
      (response as PersonalTargetCsvImportSuccess<http.Response>).value,
      successStatus: 200,
      parseSuccess: _parsePreview,
    );
  }

  @override
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportConfirmReceipt>>
  confirm({required PersonalTargetCsvImportConfirmation confirmation}) async {
    if (!_isUuid(confirmation.previewId) ||
        !_isUuid(confirmation.requestId) ||
        confirmation.rows.length > 500 ||
        confirmation.rows.length != confirmation.actions.length ||
        !_isOrderedRows(confirmation.rows) ||
        !_actionsMatchRows(confirmation.rows, confirmation.actions)) {
      return const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.invalidInput,
      );
    }
    final response = await _request(
      method: 'POST',
      path: '/v1/promotion-targets/imports/csv/confirm',
      contentType: 'application/json',
      body: {
        'preview_id': confirmation.previewId,
        'request_id': confirmation.requestId,
        'rows': confirmation.rows.map(_rowJson).toList(),
        'actions': confirmation.actions
            .map((action) => action.storageValue)
            .toList(),
      },
    );
    if (response is PersonalTargetCsvImportRejected<http.Response>) {
      return PersonalTargetCsvImportRejected(
        response.code,
        issues: response.issues,
      );
    }
    final httpResponse =
        (response as PersonalTargetCsvImportSuccess<http.Response>).value;
    if (httpResponse.statusCode == 409) {
      try {
        final root = _exactObject(jsonDecode(httpResponse.body), {'receipt'});
        final receipt = _parseConfirmReceipt(root['receipt'], confirmation);
        if (receipt.stale) return PersonalTargetCsvImportStale(receipt);
      } on FormatException {
        // A non-receipt 409 is parsed below as the fixed conflict envelope.
      }
      return _parseResult(
        httpResponse,
        successStatus: 200,
        parseSuccess: (root) => _parseSuccessfulConfirm(root, confirmation),
        successKeys: const {'receipt'},
      );
    }
    return _parseResult(
      httpResponse,
      successStatus: 200,
      parseSuccess: (root) => _parseSuccessfulConfirm(root, confirmation),
      successKeys: const {'receipt'},
    );
  }

  Future<PersonalTargetCsvImportResult<http.Response>> _request({
    required String method,
    required String path,
    required String contentType,
    List<int>? bytes,
    Map<String, Object?>? body,
  }) async {
    try {
      var token = await _identitySession.accessToken();
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return const PersonalTargetCsvImportRejected<http.Response>(
          PersonalTargetCsvImportFailureCode.unauthorized,
        );
      }
      var response = await _send(
        method,
        path,
        contentType,
        token.value,
        bytes,
        body,
      );
      if (response.statusCode == 401) {
        token = await _identitySession.accessToken(forceRefresh: true);
        if (token is! IdentitySuccess<IdentityAccessToken>) {
          return const PersonalTargetCsvImportRejected<http.Response>(
            PersonalTargetCsvImportFailureCode.unauthorized,
          );
        }
        response = await _send(
          method,
          path,
          contentType,
          token.value,
          bytes,
          body,
        );
      }
      return PersonalTargetCsvImportSuccess(response);
    } on TimeoutException {
      return const PersonalTargetCsvImportRejected<http.Response>(
        PersonalTargetCsvImportFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalTargetCsvImportRejected<http.Response>(
        PersonalTargetCsvImportFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PersonalTargetCsvImportRejected<http.Response>(
        PersonalTargetCsvImportFailureCode.malformedResponse,
      );
    } on Exception {
      return const PersonalTargetCsvImportRejected<http.Response>(
        PersonalTargetCsvImportFailureCode.networkUnavailable,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String path,
    String contentType,
    IdentityAccessToken token,
    List<int>? bytes,
    Map<String, Object?>? body,
  ) {
    final request = http.Request(method, _baseUri.resolve(path))
      ..headers.addAll({
        'authorization': 'Bearer ${token.value}',
        'accept': 'application/json',
        'content-type': contentType,
      });
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else {
      request.body = jsonEncode(body);
    }
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(_timeout);
  }

  @override
  Future<void> close() async => _client.close();
}

PersonalTargetCsvImportResult<T> _parseResult<T>(
  http.Response response, {
  required int successStatus,
  required T Function(Map<String, Object?> root) parseSuccess,
  Set<String>? successKeys,
}) {
  if (response.statusCode == successStatus) {
    try {
      final root = _exactObject(
        jsonDecode(response.body),
        successKeys ?? const {'receipt', 'rows'},
      );
      return PersonalTargetCsvImportSuccess(parseSuccess(root));
    } on FormatException {
      return const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.malformedResponse,
      );
    } on StateError {
      return const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.malformedResponse,
      );
    }
  }
  try {
    final root = _exactObject(jsonDecode(response.body), const {'error'});
    final error = _exactObject(
      root['error'],
      response.statusCode == 422 ? const {'code', 'issues'} : const {'code'},
    );
    final code = error['code'];
    final mapped = switch (response.statusCode) {
      400 when code == 'invalid_personal_target_csv_import_request' =>
        PersonalTargetCsvImportFailureCode.invalidInput,
      401 when code == 'unauthenticated' =>
        PersonalTargetCsvImportFailureCode.unauthorized,
      403 when code == 'personal_target_csv_import_forbidden' =>
        PersonalTargetCsvImportFailureCode.forbidden,
      409 when code == 'personal_target_csv_import_conflict' =>
        PersonalTargetCsvImportFailureCode.conflict,
      413 when code == 'payload_too_large' =>
        PersonalTargetCsvImportFailureCode.payloadTooLarge,
      415 when code == 'unsupported_personal_target_csv_import_media_type' =>
        PersonalTargetCsvImportFailureCode.unsupportedMediaType,
      422 when code == 'invalid_personal_target_csv_import_rows' =>
        PersonalTargetCsvImportFailureCode.invalidRows,
      503 when code == 'personal_target_csv_import_unavailable' =>
        PersonalTargetCsvImportFailureCode.serviceUnavailable,
      _ => null,
    };
    if (mapped == null ||
        (response.statusCode == 422) != error.containsKey('issues')) {
      throw const FormatException();
    }
    final issues = response.statusCode == 422
        ? _parseIssues(error['issues'])
        : const <PersonalTargetCsvImportIssue>[];
    return PersonalTargetCsvImportRejected(mapped, issues: issues);
  } on FormatException {
    return const PersonalTargetCsvImportRejected(
      PersonalTargetCsvImportFailureCode.malformedResponse,
    );
  }
}

PersonalTargetCsvImportPreview _parsePreview(Map<String, Object?> root) {
  final receipt = _parsePreviewReceipt(root['receipt']);
  final values = root['rows'];
  if (values is! List<Object?> || values.length != receipt.rowCount) {
    throw const FormatException();
  }
  final rows = <PersonalTargetCsvImportPreviewRow>[];
  for (var index = 0; index < values.length; index++) {
    final row = _exactObject(values[index], const {
      'row_number',
      'target_type',
      'display_name',
      'phone',
      'email',
      'hinted',
    });
    final type = _parseTargetType(row['target_type']);
    final displayName = _normalizedString(row['display_name'], 200);
    final phone = _nullableNormalizedString(row['phone'], 80);
    final email = _nullableNormalizedString(row['email'], 320);
    final rowNumber = _integer(row['row_number'], 1, 500);
    final hinted = row['hinted'];
    if (rowNumber != index + 1 ||
        hinted is! bool ||
        hinted != receipt.hintedRows.contains(rowNumber)) {
      throw const FormatException();
    }
    rows.add(
      PersonalTargetCsvImportPreviewRow(
        rowNumber: rowNumber,
        type: type,
        displayName: displayName,
        phone: phone,
        email: email,
        hinted: hinted,
      ),
    );
  }
  return PersonalTargetCsvImportPreview(receipt: receipt, rows: rows);
}

PersonalTargetCsvImportPreviewReceipt _parsePreviewReceipt(Object? value) {
  final root = _exactObject(value, const {
    'contract_id',
    'preview_id',
    'row_count',
    'hinted_rows',
    'previewed_at_utc',
    'expires_at_utc',
  });
  if (root['contract_id'] != _previewContract || !_isUuid(root['preview_id'])) {
    throw const FormatException();
  }
  final rowCount = _integer(root['row_count'], 0, 500);
  final hintedValue = root['hinted_rows'];
  if (hintedValue is! List<Object?>) throw const FormatException();
  final hinted = hintedValue
      .map((value) => _integer(value, 1, rowCount))
      .toList();
  if (!_strictlyIncreasing(hinted)) throw const FormatException();
  final previewed = _timestamp(root['previewed_at_utc']);
  final expires = _timestamp(root['expires_at_utc']);
  if (expires.difference(previewed) != const Duration(minutes: 15)) {
    throw const FormatException();
  }
  return PersonalTargetCsvImportPreviewReceipt(
    previewId: root['preview_id']! as String,
    rowCount: rowCount,
    hintedRows: hinted,
    previewedAtUtc: previewed,
    expiresAtUtc: expires,
  );
}

PersonalTargetCsvImportConfirmReceipt _parseConfirmReceipt(
  Object? value,
  PersonalTargetCsvImportConfirmation confirmation,
) {
  final root = _exactObject(value, const {
    'contract_id',
    'preview_id',
    'request_id',
    'outcome',
    'row_count',
    'hint_count',
    'created_count',
    'created_targets',
    'completed_at_utc',
  });
  if (root['contract_id'] != _confirmContract ||
      root['preview_id'] != confirmation.previewId ||
      root['request_id'] != confirmation.requestId ||
      (root['outcome'] != 'confirmed' && root['outcome'] != 'stale_preview')) {
    throw const FormatException();
  }
  final rowCount = _integer(root['row_count'], 0, 500);
  final hintCount = _integer(root['hint_count'], 0, rowCount);
  final createdCount = _integer(root['created_count'], 0, rowCount);
  final stale = root['outcome'] == 'stale_preview';
  final targetsValue = root['created_targets'];
  if (targetsValue is! List<Object?> ||
      rowCount != confirmation.rows.length ||
      (stale
          ? createdCount != 0
          : createdCount !=
                confirmation.actions
                    .where((a) => a != PersonalTargetCsvImportAction.skip)
                    .length) ||
      hintCount != confirmation.rows.where((row) => row.hinted).length ||
      targetsValue.length != createdCount) {
    throw const FormatException();
  }
  final targets = <PersonalTargetCsvImportCreatedTarget>[];
  for (var index = 0; index < targetsValue.length; index++) {
    final target = _exactObject(targetsValue[index], const {
      'row_number',
      'target_id',
    });
    final rowNumber = _integer(target['row_number'], 1, rowCount);
    final expectedCreatedRows = confirmation.actions
        .asMap()
        .entries
        .where((entry) => entry.value != PersonalTargetCsvImportAction.skip)
        .map((entry) => entry.key + 1)
        .toList();
    if (stale ||
        rowNumber != expectedCreatedRows[index] ||
        !_isUuid(target['target_id'])) {
      throw const FormatException();
    }
    targets.add(
      PersonalTargetCsvImportCreatedTarget(
        rowNumber: rowNumber,
        targetId: target['target_id']! as String,
      ),
    );
  }
  final targetIds = targets.map((target) => target.targetId).toSet();
  if (targetIds.length != targets.length) throw const FormatException();
  return PersonalTargetCsvImportConfirmReceipt(
    previewId: confirmation.previewId,
    requestId: confirmation.requestId,
    stale: stale,
    rowCount: rowCount,
    hintCount: hintCount,
    createdCount: createdCount,
    createdTargets: targets,
    completedAtUtc: _timestamp(root['completed_at_utc']),
  );
}

PersonalTargetCsvImportConfirmReceipt _parseSuccessfulConfirm(
  Map<String, Object?> root,
  PersonalTargetCsvImportConfirmation confirmation,
) {
  final receipt = _parseConfirmReceipt(root['receipt'], confirmation);
  if (receipt.stale) throw const FormatException();
  return receipt;
}

List<PersonalTargetCsvImportIssue> _parseIssues(Object? value) {
  if (value is! List<Object?> || value.isEmpty) throw const FormatException();
  const fields = {
    'csv',
    'header',
    'row',
    'target_type',
    'display_name',
    'phone',
    'email',
  };
  const codes = {
    'invalid_utf8',
    'malformed_csv',
    'invalid_header',
    'too_many_rows',
    'invalid_column_count',
    'invalid_value',
    'invalid_length',
  };
  return value.map((entry) {
    final issue = _exactObject(entry, const {'row_number', 'field', 'code'});
    if (!fields.contains(issue['field']) || !codes.contains(issue['code'])) {
      throw const FormatException();
    }
    return PersonalTargetCsvImportIssue(
      rowNumber: _integer(issue['row_number'], 1, 501),
      field: _string(issue['field']),
      code: _string(issue['code']),
    );
  }).toList();
}

Map<String, Object?> _rowJson(PersonalTargetCsvImportPreviewRow row) => {
  'target_type': row.type.storageValue,
  'display_name': row.displayName,
  'phone': row.phone,
  'email': row.email,
};

PromotionTargetType _parseTargetType(Object? value) =>
    PromotionTargetType.values.firstWhere(
      (type) => type.storageValue == value,
      orElse: () => throw const FormatException(),
    );

Map<String, Object?> _exactObject(Object? value, Set<String> keys) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !value.keys.toSet().containsAll(keys)) {
    throw const FormatException();
  }
  return value;
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) throw const FormatException();
  return value;
}

String _normalizedString(Object? value, int maximumLength) {
  final text = _string(value);
  if (text != text.trim() || text.runes.length > maximumLength) {
    throw const FormatException();
  }
  return text;
}

String? _nullableNormalizedString(Object? value, int maximumLength) =>
    value == null ? null : _normalizedString(value, maximumLength);

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException();
  }
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.(\d{3}|\d{6})Z$',
      ).hasMatch(value)) {
    throw const FormatException();
  }
  final timestamp = DateTime.parse(value).toUtc();
  final expected =
      '${timestamp.toIso8601String().substring(0, 19)}.'
      '${timestamp.millisecond.toString().padLeft(3, '0')}'
      '${timestamp.microsecond.toString().padLeft(3, '0')}Z';
  if (value.replaceFirstMapped(
        RegExp(r'\.(\d{3})Z$'),
        (match) => '.${match[1]}000Z',
      ) !=
      expected) {
    throw const FormatException();
  }
  return timestamp;
}

bool _isUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value);

bool _strictlyIncreasing(List<int> values) => values.asMap().entries.every(
  (entry) => entry.key == 0 || values[entry.key - 1] < entry.value,
);

bool _isOrderedRows(List<PersonalTargetCsvImportPreviewRow> rows) => rows
    .asMap()
    .entries
    .every((entry) => entry.value.rowNumber == entry.key + 1);

bool _actionsMatchRows(
  List<PersonalTargetCsvImportPreviewRow> rows,
  List<PersonalTargetCsvImportAction> actions,
) => rows.asMap().entries.every((entry) {
  final action = actions[entry.key];
  return entry.value.hinted
      ? action != PersonalTargetCsvImportAction.create
      : action != PersonalTargetCsvImportAction.createSeparate;
});
