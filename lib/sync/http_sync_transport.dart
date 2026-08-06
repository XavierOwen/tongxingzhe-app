import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../identity/identity_session.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

SyncTransport? productionSyncTransport(IdentitySession identitySession) {
  if (_backendBaseUrl.trim().isEmpty) {
    return null;
  }
  return HttpSyncTransport(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// 把 SyncEngine 的稳定 command 转成自有 Backend HTTPS 请求。
final class HttpSyncTransport implements SyncTransport, SyncBatchTransport {
  factory HttpSyncTransport({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return HttpSyncTransport._(
      _validatedBaseUri(baseUri),
      identitySession,
      client,
      timeout,
    );
  }

  HttpSyncTransport._(
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
  Future<void> close() async => _client.close();

  @override
  Future<SyncPushResult> push(SyncCommand command) async {
    try {
      final authorized = await _authorizedRequest(
        (token) => _sendCommand(command, token),
      );
      if (authorized case _RequestIdentityFailure(:final failureCode)) {
        return SyncPushRetryable(failureCode: failureCode);
      }
      return _mapPushResponse((authorized as _RequestResponse).response);
    } on TimeoutException {
      return const SyncPushRetryable(failureCode: 'network_timeout');
    } on http.ClientException {
      return const SyncPushRetryable(failureCode: 'network_unavailable');
    }
  }

  @override
  Future<List<SyncCommandPushOutcome>> pushBatch(
    List<SyncCommand> commands,
  ) async {
    if (commands.isEmpty) {
      return const [];
    }
    try {
      final authorized = await _authorizedRequest(
        (token) => _sendCommandBatch(commands, token),
      );
      if (authorized case _RequestIdentityFailure(:final failureCode)) {
        return _sameBatchResult(
          commands,
          SyncPushRetryable(failureCode: failureCode),
        );
      }
      return _mapBatchPushResponse(
        (authorized as _RequestResponse).response,
        commands,
      );
    } on TimeoutException {
      return _sameBatchResult(
        commands,
        const SyncPushRetryable(failureCode: 'network_timeout'),
      );
    } on http.ClientException {
      return _sameBatchResult(
        commands,
        const SyncPushRetryable(failureCode: 'network_unavailable'),
      );
    }
  }

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 100) {
      return const SyncPullPermanentFailure(failureCode: 'invalid_limit');
    }
    try {
      final authorized = await _authorizedRequest(
        (token) => _sendPull(scope, cursor, limit, token),
      );
      if (authorized case _RequestIdentityFailure(:final failureCode)) {
        return SyncPullRetryable(failureCode: failureCode);
      }
      return _mapPullResponse((authorized as _RequestResponse).response);
    } on TimeoutException {
      return const SyncPullRetryable(failureCode: 'network_timeout');
    } on http.ClientException {
      return const SyncPullRetryable(failureCode: 'network_unavailable');
    }
  }

  Future<_AuthorizedRequestResult> _authorizedRequest(
    Future<http.Response> Function(IdentityAccessToken token) send,
  ) async {
    final initialToken = await _identitySession.accessToken();
    if (initialToken case IdentityRejected<IdentityAccessToken>(
      :final failure,
    )) {
      return _RequestIdentityFailure(_identityFailureCode(failure.code));
    }
    var token = (initialToken as IdentitySuccess<IdentityAccessToken>).value;
    var response = await send(token);
    if (response.statusCode != 401) {
      return _RequestResponse(response);
    }
    final refreshed = await _identitySession.accessToken(forceRefresh: true);
    if (refreshed case IdentityRejected<IdentityAccessToken>(:final failure)) {
      return _RequestIdentityFailure(_identityFailureCode(failure.code));
    }
    token = (refreshed as IdentitySuccess<IdentityAccessToken>).value;
    response = await send(token);
    return _RequestResponse(response);
  }

  Future<http.Response> _sendCommand(
    SyncCommand command,
    IdentityAccessToken token,
  ) {
    return _client
        .post(
          _baseUri.resolve('/v1/sync/commands'),
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer ${token.value}',
            'content-type': 'application/json',
          },
          body: jsonEncode(_commandEnvelope(command)),
        )
        .timeout(_timeout);
  }

  Future<http.Response> _sendCommandBatch(
    List<SyncCommand> commands,
    IdentityAccessToken token,
  ) {
    return _client
        .post(
          _baseUri.resolve('/v1/sync/commands/batch'),
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer ${token.value}',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'commands': [
              for (final command in commands) _commandEnvelope(command),
            ],
          }),
        )
        .timeout(_timeout);
  }

  Map<String, Object?> _commandEnvelope(SyncCommand command) => {
    'protocol_version': command.protocolVersion,
    'command_id': command.commandId,
    'device_id': command.deviceId,
    'aggregate_id': command.aggregateId,
    'base_revision': command.baseRevision,
    'type': command.commandType,
    'typed_payload': command.payload,
  };

  Future<http.Response> _sendPull(
    SyncScope scope,
    String? cursor,
    int limit,
    IdentityAccessToken token,
  ) {
    final query = <String, String>{
      'workspace_id': scope.workspaceId,
      'project_id': scope.projectId,
      'limit': '$limit',
      'cursor': ?cursor,
    };
    final uri = _baseUri
        .resolve('/v1/sync/changes')
        .replace(queryParameters: query);
    return _client
        .get(
          uri,
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer ${token.value}',
          },
        )
        .timeout(_timeout);
  }

  SyncPushResult _mapPushResponse(http.Response response) {
    if (response.statusCode == 401) {
      return const SyncPushRetryable(failureCode: 'unauthorized');
    }
    if (response.statusCode == 403) {
      return const SyncPushPermanentFailure(failureCode: 'forbidden');
    }
    if (response.statusCode == 409) {
      return const SyncPushConflict();
    }
    if (response.statusCode == 422) {
      return SyncPushPermanentFailure(
        failureCode: _responseFailureCode(response, 'rejected'),
      );
    }
    if (response.statusCode == 429) {
      return SyncPushRetryable(
        failureCode: 'rate_limited',
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode >= 500) {
      return SyncPushRetryable(
        failureCode: 'server_unavailable',
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode != 200) {
      return SyncPushPermanentFailure(
        failureCode: _responseFailureCode(response, 'server_rejected'),
      );
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, Object?>) {
        throw const FormatException('response must be an object');
      }
      return _mapPushBody(body);
    } on FormatException {
      return const SyncPushRetryable(failureCode: 'invalid_server_response');
    }
  }

  List<SyncCommandPushOutcome> _mapBatchPushResponse(
    http.Response response,
    List<SyncCommand> commands,
  ) {
    final requestLevel = _requestLevelBatchFailure(response);
    if (requestLevel != null) {
      return _sameBatchResult(commands, requestLevel);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('batch response must be an object');
      }
      final rawResults = decoded['results'];
      if (rawResults is! List<Object?> ||
          rawResults.length != commands.length) {
        throw const FormatException('batch results do not match request');
      }
      final expectedIds = {for (final command in commands) command.commandId};
      if (expectedIds.length != commands.length) {
        throw const FormatException('batch command IDs must be unique');
      }
      final receivedIds = <String>{};
      final outcomes = <SyncCommandPushOutcome>[];
      for (final rawResult in rawResults) {
        if (rawResult is! Map<String, Object?>) {
          throw const FormatException('batch result must be an object');
        }
        final commandId = _nonEmptyString(rawResult['command_id']);
        if (!expectedIds.contains(commandId) || !receivedIds.add(commandId)) {
          throw const FormatException('unexpected batch command ID');
        }
        outcomes.add(
          SyncCommandPushOutcome(
            commandId: commandId,
            result: _mapPushBody(rawResult),
          ),
        );
      }
      return outcomes;
    } on FormatException {
      return _sameBatchResult(
        commands,
        const SyncPushRetryable(failureCode: 'invalid_server_response'),
      );
    }
  }

  SyncPushResult? _requestLevelBatchFailure(http.Response response) {
    if (response.statusCode == 200) {
      return null;
    }
    if (response.statusCode == 401) {
      return const SyncPushRetryable(failureCode: 'unauthorized');
    }
    if (response.statusCode == 403) {
      return const SyncPushPermanentFailure(failureCode: 'forbidden');
    }
    if (response.statusCode == 429) {
      return SyncPushRetryable(
        failureCode: 'rate_limited',
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode >= 500) {
      return SyncPushRetryable(
        failureCode: 'server_unavailable',
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    return SyncPushPermanentFailure(
      failureCode: _responseFailureCode(response, 'server_rejected'),
    );
  }

  SyncPushResult _mapPushBody(Map<String, Object?> body) {
    final result = body['result'];
    return switch (result) {
      'accepted' || 'duplicate' => SyncPushAccepted(
        serverCursor: _nonEmptyString(body['server_cursor']),
        duplicate: result == 'duplicate',
      ),
      'conflict' => SyncPushConflict(
        failureCode: _optionalFailureCode(body, 'conflict'),
      ),
      'rejected' => SyncPushPermanentFailure(
        failureCode: _optionalFailureCode(body, 'rejected'),
      ),
      'forbidden' => SyncPushPermanentFailure(
        failureCode: _optionalFailureCode(body, 'forbidden'),
      ),
      'retryable' => SyncPushRetryable(
        failureCode: _optionalFailureCode(body, 'server_unavailable'),
        retryAfter: _retryAfter(body['retry_after_seconds']?.toString()),
      ),
      _ => throw const FormatException('unsupported sync result'),
    };
  }

  List<SyncCommandPushOutcome> _sameBatchResult(
    List<SyncCommand> commands,
    SyncPushResult result,
  ) => [
    for (final command in commands)
      SyncCommandPushOutcome(commandId: command.commandId, result: result),
  ];

  SyncPullResult _mapPullResponse(http.Response response) {
    if (response.statusCode == 401) {
      return const SyncPullRetryable(failureCode: 'unauthorized');
    }
    if (response.statusCode == 403) {
      return const SyncPullPermanentFailure(failureCode: 'forbidden');
    }
    if (response.statusCode == 429) {
      return const SyncPullRetryable(failureCode: 'rate_limited');
    }
    if (response.statusCode >= 500) {
      return const SyncPullRetryable(failureCode: 'server_unavailable');
    }
    if (response.statusCode != 200) {
      return SyncPullPermanentFailure(
        failureCode: _responseFailureCode(response, 'server_rejected'),
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('response must be an object');
      }
      final rawChanges = decoded['changes'];
      if (rawChanges is! List<Object?>) {
        throw const FormatException('changes must be a list');
      }
      final nextCursor = decoded['next_cursor'];
      if (nextCursor != null && (nextCursor is! String || nextCursor.isEmpty)) {
        throw const FormatException('next cursor must be a string');
      }
      final changes = <SyncRemoteChange>[];
      for (final rawChange in rawChanges) {
        if (rawChange is! Map<String, Object?>) {
          throw const FormatException('change must be an object');
        }
        final changeType = rawChange['change_type'];
        final revisionNumber = rawChange['revision_number'];
        final payload = rawChange['payload'];
        if (changeType is! String ||
            changeType.isEmpty ||
            revisionNumber is! int ||
            payload is! Map<String, Object?>) {
          throw const FormatException('invalid change shape');
        }
        changes.add(
          SyncRemoteChange(
            changeType: changeType,
            revisionNumber: revisionNumber,
            payload: Map.unmodifiable(payload),
          ),
        );
      }
      if (changes.isNotEmpty && nextCursor == null) {
        throw const FormatException('non-empty changes require a cursor');
      }
      return SyncPullSucceeded(
        SyncPullBatch(changes: changes, nextCursor: nextCursor as String?),
      );
    } on FormatException {
      return const SyncPullRetryable(failureCode: 'invalid_server_response');
    }
  }

  String _responseFailureCode(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, Object?>) {
        return _optionalFailureCode(body, fallback);
      }
    } on FormatException {
      // HTTP 状态仍提供稳定分类；无效错误正文不进入 UI。
    }
    return fallback;
  }

  String _optionalFailureCode(Map<String, Object?> body, String fallback) {
    final error = body['error'];
    if (error is Map<String, Object?>) {
      final code = error['code'];
      if (code is String && code.trim().isNotEmpty) {
        return code.trim();
      }
    }
    return fallback;
  }

  String _nonEmptyString(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('server cursor is required');
    }
    return value;
  }

  Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    if (seconds == null || seconds < 0) {
      return null;
    }
    return Duration(seconds: seconds.clamp(0, 3600));
  }

  String _identityFailureCode(IdentityFailureCode code) {
    return switch (code) {
      IdentityFailureCode.rateLimited => 'identity_rate_limited',
      IdentityFailureCode.networkUnavailable => 'identity_network_unavailable',
      IdentityFailureCode.sessionMissing => 'identity_session_missing',
      _ => 'identity_unavailable',
    };
  }
}

sealed class _AuthorizedRequestResult {
  const _AuthorizedRequestResult();
}

final class _RequestResponse extends _AuthorizedRequestResult {
  const _RequestResponse(this.response);

  final http.Response response;
}

final class _RequestIdentityFailure extends _AuthorizedRequestResult {
  const _RequestIdentityFailure(this.failureCode);

  final String failureCode;
}

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('BACKEND_BASE_URL must be an absolute URL');
  }
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'BACKEND_BASE_URL must use HTTPS except on localhost',
    );
  }
  return value;
}
