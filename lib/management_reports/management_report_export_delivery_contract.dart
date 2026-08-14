import 'management_report_gateway.dart';

/// The second-stage capability that asks a platform to deliver a validated
/// management-report export artifact.
///
/// A successful result means that the platform accepted the request. It does
/// not mean that a browser saved, opened, or retained the file.
abstract interface class ManagementReportExportDelivery {
  bool get isAvailable;

  Future<ManagementReportExportDeliveryResult> requestDownload(
    ManagementReportExportArtifact artifact,
  );
}

sealed class ManagementReportExportDeliveryResult {
  const ManagementReportExportDeliveryResult();
}

final class ManagementReportDownloadRequested
    extends ManagementReportExportDeliveryResult {
  const ManagementReportDownloadRequested();
}

final class ManagementReportDownloadUnavailable
    extends ManagementReportExportDeliveryResult {
  const ManagementReportDownloadUnavailable();
}

final class ManagementReportDownloadFailed
    extends ManagementReportExportDeliveryResult {
  const ManagementReportDownloadFailed([this.error, this.stackTrace]);

  final Object? error;
  final StackTrace? stackTrace;
}

/// Explicit unsupported adapter used by native and other non-Web targets.
final class UnsupportedManagementReportExportDelivery
    implements ManagementReportExportDelivery {
  const UnsupportedManagementReportExportDelivery();

  @override
  bool get isAvailable => false;

  @override
  Future<ManagementReportExportDeliveryResult> requestDownload(
    ManagementReportExportArtifact artifact,
  ) async => const ManagementReportDownloadUnavailable();
}
