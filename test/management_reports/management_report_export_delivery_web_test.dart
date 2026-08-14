@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/management_reports/management_report_export_delivery_contract.dart';
import 'package:tongxingzhe_app/management_reports/management_report_export_delivery_web.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'Web adapter sends the exact artifact through a temporary anchor',
    () async {
      final artifact = _artifact();
      final urlConstructor = globalContext['URL']! as JSObject;
      final originalCreateObjectUrl =
          urlConstructor['createObjectURL']! as JSFunction;
      final originalRevokeObjectUrl =
          urlConstructor['revokeObjectURL']! as JSFunction;
      web.Blob? capturedBlob;
      final revokedUrls = <String>[];
      final createObjectUrlSpy = ((web.Blob blob) {
        capturedBlob = blob;
        return originalCreateObjectUrl.callAsFunction(urlConstructor, blob)!
            as JSString;
      }).toJS;
      final revokeObjectUrlSpy = ((JSString objectUrl) {
        revokedUrls.add(objectUrl.toDart);
        originalRevokeObjectUrl.callAsFunction(urlConstructor, objectUrl);
      }).toJS;
      urlConstructor['createObjectURL'] = createObjectUrlSpy;
      urlConstructor['revokeObjectURL'] = revokeObjectUrlSpy;
      addTearDown(() {
        urlConstructor['createObjectURL'] = originalCreateObjectUrl;
        urlConstructor['revokeObjectURL'] = originalRevokeObjectUrl;
      });

      String? capturedHref;
      String? capturedFileName;
      String? capturedContentType;

      late web.EventListener clickListener;
      clickListener = ((web.Event event) {
        final anchor = event.target as web.HTMLAnchorElement?;
        if (anchor == null || capturedHref != null) return;

        event.preventDefault();
        capturedHref = anchor.href;
        capturedFileName = anchor.download;
        capturedContentType = anchor.type;
      }).toJS;
      web.document.addEventListener('click', clickListener, true.toJS);
      addTearDown(
        () =>
            web.document.removeEventListener('click', clickListener, true.toJS),
      );

      final result = await const WebManagementReportExportDelivery()
          .requestDownload(artifact);
      final blob = capturedBlob!;

      expect(result, isA<ManagementReportDownloadRequested>());
      expect(capturedFileName, artifact.fileName);
      expect(capturedContentType, artifact.contentType);
      expect(blob.type, artifact.contentType);
      expect(blob.size, artifact.bytes.length);
      final buffer = await blob.arrayBuffer().toDart;
      expect(Uint8List.view(buffer.toDart), artifact.bytes);
      expect(web.document.querySelector('a[download]'), isNull);

      await Future<void>.delayed(Duration.zero);
      expect(revokedUrls, [capturedHref]);
      // The user agent is retained in test logs as versioned runtime evidence.
      // This test prevents the save action, so it proves a request, not a save.
      // ignore: avoid_print
      print('Web download request evidence: ${web.window.navigator.userAgent}');
    },
  );
}

ManagementReportExportArtifact _artifact() => ManagementReportExportArtifact(
  bytes: const [0, 1, 2, 127, 128, 255],
  fileName: 'management-report.json',
  contentType: 'application/json; charset=utf-8',
  exportEventId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  snapshot: ManagementReportSnapshot(
    summary: ManagementReportSnapshotSummary(
      snapshotId: 'snapshot-1',
      reportId: 'report-1',
      reportVersion: 1,
      reportingTimeZone: 'America/Chicago',
      dataCutoffUtc: DateTime.utc(2030, 3, 11),
      releasedAtUtc: DateTime.utc(2030, 3, 11, 1),
    ),
    report: ProtectedManagementReport(
      reportId: 'report-1',
      reportVersion: 1,
      metricId: 'contact_sessions',
      metricVersion: 1,
      dimension: 'channel',
      queryFingerprint: 'test',
      privacyPolicy: 'test',
      sourceScope: 'test',
      projectId: 'project-1',
      periodBoundaryId: 'test',
      reportingTimeZone: 'America/Chicago',
      dataCutoffUtc: DateTime.utc(2030, 3, 11),
      previousPeriod: ManagementReportPeriod(
        startUtc: DateTime.utc(2030, 2, 25),
        untilUtc: DateTime.utc(2030, 3, 4),
      ),
      currentPeriod: ManagementReportPeriod(
        startUtc: DateTime.utc(2030, 3, 4),
        untilUtc: DateTime.utc(2030, 3, 11),
      ),
      cells: const [],
    ),
  ),
);
