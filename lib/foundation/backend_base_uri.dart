Uri validateBackendBaseUri(Uri value) {
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

Uri validateManagementReportBaseUri(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('Backend URL must be absolute');
  }
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'Backend URL must use HTTPS except on localhost',
    );
  }
  if (value.userInfo.isNotEmpty || value.hasQuery || value.hasFragment) {
    throw const FormatException('Backend URL contains unsupported components');
  }
  return value;
}

Uri validatePathlessBackendBaseUri(Uri value) {
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if ((value.scheme != 'https' && !localHttp) ||
      value.host.isEmpty ||
      value.path.isNotEmpty && value.path != '/') {
    throw ArgumentError('invalid backend base URI');
  }
  return value;
}

Uri validateAbsoluteBaseUri(Uri value) {
  if (!value.hasScheme || !value.hasAuthority) {
    throw ArgumentError.value(value, 'baseUri', 'must be an absolute URI');
  }
  return value;
}
