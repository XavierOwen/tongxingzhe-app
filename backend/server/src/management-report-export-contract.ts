export interface ManagementReportSnapshotExportDocument {
  readonly export_contract_id: "management_report_snapshot_export_v1";
  readonly snapshot_id: string;
  readonly released_at_utc: string;
  readonly report: ManagementReportSnapshotExportReport;
}

export interface ManagementReportSnapshotExportReport {
  readonly report_id: "contact_sessions_by_channel_two_periods";
  readonly report_version: 1;
  readonly metric_id: "contact_sessions";
  readonly metric_version: 1;
  readonly dimension: "channel";
  readonly query_fingerprint:
    "management-report:contact_sessions_by_channel_two_periods:v1";
  readonly privacy_policy: "management_contact_session_privacy_v1";
  readonly source_scope: "backend_accepted_contacts";
  readonly project_id: string;
  readonly periods: ManagementReportSnapshotExportPeriods;
  readonly cells: readonly ManagementReportSnapshotExportCell[];
}

interface ManagementReportSnapshotExportPeriods {
  readonly period_boundary_id: "iso_week_monday_v1";
  readonly reporting_time_zone: string;
  readonly data_cutoff_utc: string;
  readonly previous_period: ManagementReportSnapshotExportPeriod;
  readonly current_period: ManagementReportSnapshotExportPeriod;
}

interface ManagementReportSnapshotExportPeriod {
  readonly start_utc: string;
  readonly until_utc: string;
}

interface ManagementReportSnapshotExportCell {
  readonly period_key: "previous" | "current";
  readonly category_key: string;
  readonly cell_order: number;
  readonly privacy_status: "displayed" | "suppressed";
  readonly value_count: number | null;
}

export function serializeManagementReportSnapshotExport(
  value: unknown,
): string {
  return JSON.stringify(parseExportDocument(value));
}

function parseExportDocument(
  value: unknown,
): ManagementReportSnapshotExportDocument {
  const root = object(value);
  requireExactKeys(root, [
    "export_contract_id",
    "snapshot_id",
    "released_at_utc",
    "report",
  ]);
  if (root.export_contract_id !== "management_report_snapshot_export_v1") {
    throw invalidExportDocument();
  }

  const releasedAtUtc = utcTimestamp(root.released_at_utc);
  const report = parseReport(root.report);
  if (releasedAtUtc < report.periods.data_cutoff_utc) {
    throw invalidExportDocument();
  }
  return {
    export_contract_id: "management_report_snapshot_export_v1",
    snapshot_id: uuid(root.snapshot_id),
    released_at_utc: releasedAtUtc,
    report,
  };
}

function parseReport(value: unknown): ManagementReportSnapshotExportReport {
  const report = object(value);
  requireExactKeys(report, [
    "report_id",
    "report_version",
    "metric_id",
    "metric_version",
    "dimension",
    "query_fingerprint",
    "privacy_policy",
    "source_scope",
    "project_id",
    "periods",
    "cells",
  ]);
  if (
    report.report_id !== "contact_sessions_by_channel_two_periods" ||
    report.report_version !== 1 ||
    report.metric_id !== "contact_sessions" ||
    report.metric_version !== 1 ||
    report.dimension !== "channel" ||
    report.query_fingerprint !==
      "management-report:contact_sessions_by_channel_two_periods:v1" ||
    report.privacy_policy !== "management_contact_session_privacy_v1" ||
    report.source_scope !== "backend_accepted_contacts"
  ) {
    throw invalidExportDocument();
  }
  return {
    report_id: "contact_sessions_by_channel_two_periods",
    report_version: 1,
    metric_id: "contact_sessions",
    metric_version: 1,
    dimension: "channel",
    query_fingerprint:
      "management-report:contact_sessions_by_channel_two_periods:v1",
    privacy_policy: "management_contact_session_privacy_v1",
    source_scope: "backend_accepted_contacts",
    project_id: uuid(report.project_id),
    periods: parsePeriods(report.periods),
    cells: parseCells(report.cells),
  };
}

function parsePeriods(value: unknown): ManagementReportSnapshotExportPeriods {
  const periods = object(value);
  requireExactKeys(periods, [
    "period_boundary_id",
    "reporting_time_zone",
    "data_cutoff_utc",
    "previous_period",
    "current_period",
  ]);
  if (
    periods.period_boundary_id !== "iso_week_monday_v1" ||
    typeof periods.reporting_time_zone !== "string" ||
    periods.reporting_time_zone.length === 0 ||
    periods.reporting_time_zone.length > 255 ||
    !timeZonePattern.test(periods.reporting_time_zone)
  ) {
    throw invalidExportDocument();
  }
  const dataCutoffUtc = utcTimestamp(periods.data_cutoff_utc);
  const previous = parsePeriod(periods.previous_period);
  const current = parsePeriod(periods.current_period);
  if (
    previous.start_utc >= previous.until_utc ||
    previous.until_utc !== current.start_utc ||
    current.start_utc >= current.until_utc ||
    current.until_utc > dataCutoffUtc
  ) {
    throw invalidExportDocument();
  }
  return {
    period_boundary_id: "iso_week_monday_v1",
    reporting_time_zone: periods.reporting_time_zone,
    data_cutoff_utc: dataCutoffUtc,
    previous_period: previous,
    current_period: current,
  };
}

function parsePeriod(value: unknown): ManagementReportSnapshotExportPeriod {
  const period = object(value);
  requireExactKeys(period, ["start_utc", "until_utc"]);
  return {
    start_utc: utcTimestamp(period.start_utc),
    until_utc: utcTimestamp(period.until_utc),
  };
}

function parseCells(value: unknown): readonly ManagementReportSnapshotExportCell[] {
  if (!Array.isArray(value) || value.length !== expectedCells.length) {
    throw invalidExportDocument();
  }
  return value.map((item, index) => {
    const cell = object(item);
    requireExactKeys(cell, [
      "period_key",
      "category_key",
      "cell_order",
      "privacy_status",
      "value_count",
    ]);
    const expected = expectedCells[index]!;
    if (
      cell.period_key !== expected.period_key ||
      cell.category_key !== expected.category_key ||
      cell.cell_order !== index ||
      (cell.privacy_status !== "displayed" &&
        cell.privacy_status !== "suppressed")
    ) {
      throw invalidExportDocument();
    }
    const valueCount = cell.value_count;
    if (
      (cell.privacy_status === "displayed" &&
        (!Number.isSafeInteger(valueCount) || Number(valueCount) < 10)) ||
      (cell.privacy_status === "suppressed" && valueCount !== null)
    ) {
      throw invalidExportDocument();
    }
    return {
      period_key: expected.period_key,
      category_key: expected.category_key,
      cell_order: index,
      privacy_status: cell.privacy_status,
      value_count: cell.privacy_status === "displayed"
        ? Number(valueCount)
        : null,
    };
  });
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidExportDocument();
  }
  return value as Record<string, unknown>;
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidExportDocument();
  }
  return value.toLowerCase();
}

function utcTimestamp(value: unknown): string {
  if (typeof value !== "string" || !rfc3339Pattern.test(value)) {
    throw invalidExportDocument();
  }
  const timestamp = new Date(value);
  if (!Number.isFinite(timestamp.getTime())) throw invalidExportDocument();
  return timestamp.toISOString();
}

function requireExactKeys(
  value: Readonly<Record<string, unknown>>,
  expected: readonly string[],
): void {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  if (
    actual.length !== sortedExpected.length ||
    actual.some((key, index) => key !== sortedExpected[index])
  ) {
    throw invalidExportDocument();
  }
}

function invalidExportDocument(): Error {
  return new Error("invalid management report snapshot export document");
}

const categories = [
  "all",
  "face_to_face",
  "voice_call",
  "video_call",
  "instant_text",
  "asynchronous_message",
  "mixed",
  "other_direct",
] as const;
const expectedCells = (["previous", "current"] as const).flatMap(
  (periodKey) => categories.map((categoryKey) => ({
    period_key: periodKey,
    category_key: categoryKey,
  })),
);
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const timeZonePattern = /^[A-Za-z0-9._+/-]+$/;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
