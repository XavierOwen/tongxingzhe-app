import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/foundation/backend_base_uri.dart';

void main() {
  test('backend validators preserve their four existing URI contracts', () {
    final https = Uri.parse('https://api.example.test/root');
    final localHttp = Uri.parse('http://localhost:8080');

    expect(validateBackendBaseUri(https), https);
    expect(validateBackendBaseUri(localHttp), localHttp);
    expect(
      () => validateBackendBaseUri(Uri.parse('http://api.example.test')),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'BACKEND_BASE_URL must use HTTPS except on localhost',
        ),
      ),
    );

    expect(validateManagementReportBaseUri(https), https);
    expect(
      () => validateManagementReportBaseUri(
        Uri.parse('https://user@api.example.test?query=1'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Backend URL contains unsupported components',
        ),
      ),
    );

    expect(validatePathlessBackendBaseUri(localHttp), localHttp);
    expect(
      () => validatePathlessBackendBaseUri(https),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          'invalid backend base URI',
        ),
      ),
    );

    expect(validateAbsoluteBaseUri(https), https);
    expect(
      () => validateAbsoluteBaseUri(Uri.parse('/relative')),
      throwsArgumentError,
    );
  });
}
