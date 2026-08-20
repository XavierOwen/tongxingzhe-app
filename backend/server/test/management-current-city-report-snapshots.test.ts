import assert from "node:assert/strict";
import test from "node:test";

import {
  ManagementCurrentCityReportSnapshotStoreError,
  PostgresManagementCurrentCityReportSnapshotStore,
} from "../src/management-current-city-report-snapshots.js";

const identity = {
  issuer: "https://runtime-current-city.synthetic/auth/v1",
  subject: "view-only-member",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const snapshotId = "88888888-8888-4888-8888-888888888888";
const accessEventId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const dataCutoffUtc = "2026-06-17T12:34:56.000Z";
const protectedReport = {
  report_id: "contact_sessions_by_current_city_two_periods",
  report_version: 1,
  metric_id: "contact_sessions",
  metric_version: 1,
  dimension: "current_city",
  view_mode: "current",
  region_granularity: "city",
  query_fingerprint:
    "management-report:contact_sessions_by_current_city_two_periods:v1",
  privacy_policy: "management_current_city_contact_session_privacy_v1",
  source_scope: "backend_accepted_active_contacts_current_revision",
  project_id: projectId,
  periods: {
    period_boundary_id: "iso_week_monday_v1",
    reporting_time_zone: "UTC",
    data_cutoff_utc: dataCutoffUtc,
    previous_period: {
      start_utc: "2026-06-01T00:00:00.000Z",
      until_utc: "2026-06-08T00:00:00.000Z",
    },
    current_period: {
      start_utc: "2026-06-08T00:00:00.000Z",
      until_utc: "2026-06-15T00:00:00.000Z",
    },
  },
  data_cutoff_utc: dataCutoffUtc,
  source_change_sequence: 0,
  target_context: {
    target_context_contract_id: "management-region-target-context:v1",
    result_status: "selected",
    reason_code: "publication_selection",
    data_cutoff_utc: dataCutoffUtc,
    target_tree_version: "fixture-target-v1",
    target_content_fingerprint: "0000000000000000000000000000000000000000000000000000000000000000",
    selection_sequence: 1,
    selection_source: "publication",
    selection_evidence_at_utc: "2026-06-01T00:00:00.000Z",
    tree_published_at_utc: "2026-06-01T00:00:00.000Z",
  },
  result_status: "completed",
  cells: [
    {
      period_key: "previous",
      city_id: "fixture-city",
      cell_order: 0,
      privacy_status: "displayed",
      value_count: 10,
    },
    {
      period_key: "current",
      city_id: "fixture-city",
      cell_order: 1,
      privacy_status: "suppressed",
      value_count: null,
    },
  ],
};

test("Postgres adapter calls only the current-city runtime bridge", async () => {
  const calls: Array<{
    readonly text: string;
    readonly values: readonly unknown[];
  }> = [];
  const store = new PostgresManagementCurrentCityReportSnapshotStore(
    async (text, values) => {
      calls.push({text, values});
      return {
        rows: [{
          access_result: {
            access_contract_id:
              "authorized_current_city_management_report_snapshot_read_v1",
            access_event_id: accessEventId,
            requested_snapshot_id: snapshotId,
            resolved_snapshot_id: snapshotId,
            result_status: "completed",
            reason_code: null,
            protected_report: protectedReport,
          },
        }],
      };
    },
  );

  const result = await store.read(identity, projectId, snapshotId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.read_authorized_management_current_city_report_snapshot_v1/,
  );
  assert.doesNotMatch(
    calls[0]?.text ?? "",
    /BEGIN|COMMIT|app_private|read_authorized_management_report_snapshot_v1/i,
  );
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    projectId,
    snapshotId,
  ]);
  assert.deepEqual(result, {
    status: "completed",
    accessEventId,
    requestedSnapshotId: snapshotId,
    resolvedSnapshotId: snapshotId,
    protectedReport,
  });
});

test("adapter rejects channel-shaped or value-bearing current-city results", async () => {
  const channelStore = new PostgresManagementCurrentCityReportSnapshotStore(
    async () => ({
      rows: [{
        access_result: {
          access_contract_id: "authorized_management_report_snapshot_read_v1",
          access_event_id: accessEventId,
          requested_snapshot_id: snapshotId,
          resolved_snapshot_id: snapshotId,
          result_status: "completed",
          reason_code: null,
          protected_report: protectedReport,
        },
      }],
    }),
  );
  await assert.rejects(
    channelStore.read(identity, projectId, snapshotId),
    /invalid current-city management report snapshot access result/,
  );

  const rewrittenContractStore =
    new PostgresManagementCurrentCityReportSnapshotStore(async () => ({
      rows: [{
        access_result: {
          access_contract_id:
            "authorized_current_city_management_report_snapshot_read_v1",
          access_event_id: accessEventId,
          project_id: projectId,
          requested_snapshot_id: snapshotId,
          resolved_snapshot_id: snapshotId,
          result_status: "completed",
          reason_code: null,
          protected_report: protectedReport,
        },
      }],
    }));
  await assert.rejects(
    rewrittenContractStore.read(identity, projectId, snapshotId),
    /invalid current-city management report snapshot access result/,
  );

  const locationStore = new PostgresManagementCurrentCityReportSnapshotStore(
    async () => ({
      rows: [{
        access_result: {
          access_contract_id:
            "authorized_current_city_management_report_snapshot_read_v1",
          access_event_id: accessEventId,
          requested_snapshot_id: snapshotId,
          resolved_snapshot_id: snapshotId,
          result_status: "completed",
          reason_code: null,
          protected_report: {
            ...protectedReport,
            cells: [{
              ...protectedReport.cells[0],
              location_source: {latitude: 41.78, longitude: -87.59},
            }, protectedReport.cells[1]],
          },
        },
      }],
    }),
  );
  await assert.rejects(
    locationStore.read(identity, projectId, snapshotId),
    /invalid current-city management report snapshot access result/,
  );
});

test("adapter rejects drift in every protected current-city contract layer", async () => {
  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    ["extra root field", {...protectedReport, city_name: "Chicago"}],
    [
      "wrong project",
      {
        ...protectedReport,
        project_id: "44444444-4444-4444-8444-444444444444",
      },
    ],
    [
      "wrong query fingerprint",
      {...protectedReport, query_fingerprint: "management-report:channel:v1"},
    ],
    [
      "period discontinuity",
      {
        ...protectedReport,
        periods: {
          ...protectedReport.periods,
          current_period: {
            ...protectedReport.periods.current_period,
            start_utc: "2026-06-09T00:00:00.000Z",
          },
        },
      },
    ],
    [
      "target fingerprint drift",
      {
        ...protectedReport,
        target_context: {
          ...protectedReport.target_context,
          target_content_fingerprint: "not-a-fingerprint",
        },
      },
    ],
    [
      "cell order drift",
      {
        ...protectedReport,
        cells: [
          protectedReport.cells[0],
          {...protectedReport.cells[1], cell_order: 0},
        ],
      },
    ],
    [
      "suppressed value restored",
      {
        ...protectedReport,
        cells: [
          protectedReport.cells[0],
          {...protectedReport.cells[1], value_count: 0},
        ],
      },
    ],
    [
      "city name attached to a cell",
      {
        ...protectedReport,
        cells: [
          {...protectedReport.cells[0], city_name: "Chicago"},
          protectedReport.cells[1],
        ],
      },
    ],
  ];

  for (const [name, report] of invalidReports) {
    const store = new PostgresManagementCurrentCityReportSnapshotStore(
      async () => ({
        rows: [{
          access_result: {
            access_contract_id:
              "authorized_current_city_management_report_snapshot_read_v1",
            access_event_id: accessEventId,
            requested_snapshot_id: snapshotId,
            resolved_snapshot_id: snapshotId,
            result_status: "completed",
            reason_code: null,
            protected_report: report,
          },
        }],
      }),
    );
    await assert.rejects(
      store.read(identity, projectId, snapshotId),
      /invalid current-city management report snapshot access result/,
      name,
    );
  }
});

test("adapter preserves value-free database outcomes", async () => {
  const cases = [
    {
      result_status: "not_found",
      reason_code: "snapshot_not_available",
      resolved_snapshot_id: null,
    },
    {
      result_status: "untrusted_provenance",
      reason_code: "snapshot_provenance_untrusted",
      resolved_snapshot_id: snapshotId,
    },
  ] as const;

  for (const outcome of cases) {
    const store = new PostgresManagementCurrentCityReportSnapshotStore(
      async () => ({
        rows: [{
          access_result: {
            access_contract_id:
              "authorized_current_city_management_report_snapshot_read_v1",
            access_event_id: accessEventId,
            requested_snapshot_id: snapshotId,
            ...outcome,
          },
        }],
      }),
    );
    const result = await store.read(identity, projectId, snapshotId);
    assert.equal(result.status, outcome.result_status);
    assert.equal("protectedReport" in result, false);
  }
});

test("adapter maps database authorization without exposing its message", async () => {
  const forbidden = new PostgresManagementCurrentCityReportSnapshotStore(
    async () => {
      throw Object.assign(new Error("private current-city grant detail"), {
        code: "42501",
      });
    },
  );

  await assert.rejects(
    forbidden.read(identity, projectId, snapshotId),
    (error: unknown) =>
      error instanceof ManagementCurrentCityReportSnapshotStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("grant"),
  );
});
