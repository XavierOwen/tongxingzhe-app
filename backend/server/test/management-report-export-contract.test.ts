import assert from "node:assert/strict";
import test from "node:test";

import {
  serializeManagementReportSnapshotExport,
} from "../src/management-report-export-contract.js";

const snapshotId = "88888888-8888-4888-8888-888888888888";
const projectId = "33333333-3333-4333-8333-333333333333";

test("canonical JSON v1 has fixed keys, cell order, and bytes", () => {
  const document = validDocument();
  const first = serializeManagementReportSnapshotExport(document);
  const second = serializeManagementReportSnapshotExport({
    report: document.report,
    released_at_utc: document.released_at_utc,
    snapshot_id: document.snapshot_id,
    export_contract_id: document.export_contract_id,
  });

  assert.equal(first, second);
  assert.equal(
    first,
    JSON.stringify({
      export_contract_id: "management_report_snapshot_export_v1",
      snapshot_id: snapshotId,
      released_at_utc: "2030-01-15T12:34:56.789Z",
      report: validReport(),
    }),
  );
  assert.equal(Buffer.byteLength(first, "utf8"), first.length);
});

test("canonical JSON v1 preserves suppressed null instead of zero", () => {
  const serialized = serializeManagementReportSnapshotExport(validDocument());
  const parsed = JSON.parse(serialized) as {
    report: {cells: Array<{privacy_status: string; value_count: number | null}>};
  };

  const suppressed = parsed.report.cells.filter(
    (cell) => cell.privacy_status === "suppressed",
  );
  assert.equal(suppressed.length, 12);
  assert.ok(suppressed.every((cell) => cell.value_count === null));
});

test("canonical JSON v1 rejects extra, private, and malformed fields", () => {
  const cases: unknown[] = [
    {...validDocument(), export_event_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"},
    {
      ...validDocument(),
      report: {...validReport(), organization_name: "Private organization"},
    },
    {
      ...validDocument(),
      report: {
        ...validReport(),
        cells: validCells().map((cell, index) => index === 0
          ? {...cell, latitude: 41.7897}
          : cell),
      },
    },
    {
      ...validDocument(),
      report: {
        ...validReport(),
        cells: validCells().map((cell, index) => index === 1
          ? {...cell, value_count: 0}
          : cell),
      },
    },
    {
      ...validDocument(),
      report: {...validReport(), cells: validCells().slice(0, 15)},
    },
    {
      ...validDocument(),
      released_at_utc: "2030-01-01T00:00:00.000Z",
    },
    {
      ...validDocument(),
      report: {
        ...validReport(),
        cells: validCells().map((cell, index) => index === 0
          ? {...cell, cell_order: 1}
          : cell),
      },
    },
    {
      ...validDocument(),
      report: {
        ...validReport(),
        cells: validCells().map((cell, index) => index === 0
          ? {...cell, value_count: Number.MAX_SAFE_INTEGER + 1}
          : cell),
      },
    },
  ];

  for (const value of cases) {
    assert.throws(
      () => serializeManagementReportSnapshotExport(value),
      /invalid management report snapshot export document/,
    );
  }
});

function validDocument() {
  return {
    export_contract_id: "management_report_snapshot_export_v1",
    snapshot_id: snapshotId,
    released_at_utc: "2030-01-15T12:34:56.789Z",
    report: validReport(),
  };
}

function validReport() {
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
    project_id: projectId,
    periods: {
      period_boundary_id: "iso_week_monday_v1",
      reporting_time_zone: "America/Chicago",
      data_cutoff_utc: "2030-01-14T06:00:00.000Z",
      previous_period: {
        start_utc: "2029-12-31T06:00:00.000Z",
        until_utc: "2030-01-07T06:00:00.000Z",
      },
      current_period: {
        start_utc: "2030-01-07T06:00:00.000Z",
        until_utc: "2030-01-14T06:00:00.000Z",
      },
    },
    cells: validCells(),
  };
}

function validCells() {
  const categories = [
    "all",
    "face_to_face",
    "voice_call",
    "video_call",
    "instant_text",
    "asynchronous_message",
    "mixed",
    "other_direct",
  ];
  return ["previous", "current"].flatMap((periodKey, periodIndex) =>
    categories.map((categoryKey, categoryIndex) => {
      const displayed = categoryKey === "all" || categoryKey === "voice_call";
      return {
        period_key: periodKey,
        category_key: categoryKey,
        cell_order: periodIndex * categories.length + categoryIndex,
        privacy_status: displayed ? "displayed" : "suppressed",
        value_count: displayed ? 10 : null,
      };
    })
  );
}
