import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/management_reports/management_report_export_delivery.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';

void main() {
  test('non-Web production delivery is explicitly unavailable', () async {
    final delivery = productionManagementReportExportDelivery();

    if (delivery.isAvailable) return;

    expect(delivery, isA<UnsupportedManagementReportExportDelivery>());
    expect(delivery.isAvailable, isFalse);
    final result = await delivery.requestDownload(_artifact());

    expect(result, isA<ManagementReportDownloadUnavailable>());
  });

  test('Web production delivery requests the browser download', () async {
    final delivery = productionManagementReportExportDelivery();

    if (!delivery.isAvailable) return;

    final result = await delivery.requestDownload(_artifact());

    expect(result, isA<ManagementReportDownloadRequested>());
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'delivery outcomes have only requested, unavailable, and failed states',
    () {
      const requested = ManagementReportDownloadRequested();
      const unavailable = ManagementReportDownloadUnavailable();
      const failed = ManagementReportDownloadFailed('test failure');

      expect(requested, isA<ManagementReportExportDeliveryResult>());
      expect(unavailable, isA<ManagementReportExportDeliveryResult>());
      expect(failed, isA<ManagementReportExportDeliveryResult>());
      expect(failed.error, 'test failure');
    },
  );
}

ManagementReportExportArtifact _artifact() => ManagementReportExportArtifact(
  bytes: const [123, 125],
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
