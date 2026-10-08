/// The validated, in-memory file fields required by a platform delivery
/// adapter.
abstract interface class ExportDownloadArtifact {
  List<int> get bytes;
  String get fileName;
  String get contentType;
}

/// The second-stage capability that asks a platform to deliver a validated
/// management-report export artifact.
///
/// A successful result means that the platform accepted the request. It does
/// not mean that a browser saved, opened, or retained the file.
abstract interface class ManagementReportExportDelivery {
  bool get isAvailable;

  Future<ManagementReportExportDeliveryResult> requestDownload(
    ExportDownloadArtifact artifact,
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
    ExportDownloadArtifact artifact,
  ) async => const ManagementReportDownloadUnavailable();
}
