import 'management_report_export_delivery_contract.dart';
import 'management_report_export_delivery_none.dart'
    if (dart.library.js_interop) 'management_report_export_delivery_web.dart'
    as platform;

export 'management_report_export_delivery_contract.dart';

/// Selects the delivery adapter for the current compilation target.
ManagementReportExportDelivery productionManagementReportExportDelivery() =>
    platform.productionManagementReportExportDelivery();
