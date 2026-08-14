import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'management_report_export_delivery_contract.dart';
import 'management_report_gateway.dart';

/// Browser adapter for requesting a download of a validated export artifact.
final class WebManagementReportExportDelivery
    implements ManagementReportExportDelivery {
  const WebManagementReportExportDelivery();

  @override
  bool get isAvailable => true;

  @override
  Future<ManagementReportExportDeliveryResult> requestDownload(
    ManagementReportExportArtifact artifact,
  ) async {
    String? objectUrl;
    web.HTMLAnchorElement? anchor;
    try {
      final blob = web.Blob(
        <web.BlobPart>[Uint8List.fromList(artifact.bytes).toJS].toJS,
        web.BlobPropertyBag(type: artifact.contentType),
      );
      objectUrl = web.URL.createObjectURL(blob);

      final body = web.document.body;
      if (body == null) {
        throw StateError('browser document body is unavailable');
      }

      anchor = web.HTMLAnchorElement()
        ..href = objectUrl
        ..download = artifact.fileName
        ..type = artifact.contentType;
      body.append(anchor);
      anchor.click();

      return const ManagementReportDownloadRequested();
    } catch (error, stackTrace) {
      return ManagementReportDownloadFailed(error, stackTrace);
    } finally {
      anchor?.remove();
      if (objectUrl case final url?) {
        // Keep the object URL alive through the click task. Revoking it
        // synchronously can cancel the browser's download in some engines.
        Timer.run(() => web.URL.revokeObjectURL(url));
      }
    }
  }
}

ManagementReportExportDelivery productionManagementReportExportDelivery() =>
    const WebManagementReportExportDelivery();
