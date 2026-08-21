import assert from "node:assert/strict";
import test from "node:test";

import {
  ManagementInterestReportSnapshotStoreError,
  PostgresManagementInterestReportSnapshotStore,
} from "../src/management-interest-report-snapshots.js";

const identity = {
  issuer: "https://runtime-interest.synthetic/auth/v1",
  subject: "view-only-member",
};
const projectId = "6d130000-0000-4000-8000-000000000001";
const otherProjectId = "6d130000-0000-4000-8000-000000000002";
const snapshotId = "6da00000-0000-4000-8000-000000000001";
const accessEventId = "6dd00000-0000-4000-8000-000000000001";

const periods = {
  period_boundary_id: "iso_week_monday_v1",
  reporting_time_zone: "UTC",
  data_cutoff_utc: "2026-06-17T12:34:56.000Z",
  previous_period: {
    start_utc: "2026-06-01T00:00:00.000Z",
    until_utc: "2026-06-08T00:00:00.000Z",
  },
  current_period: {
    start_utc: "2026-06-08T00:00:00.000Z",
    until_utc: "2026-06-15T00:00:00.000Z",
  },
};

function cells(
  previous: "displayed" | "suppressed" = "displayed",
  current: "displayed" | "suppressed" = "suppressed",
) {
  return Array.from({length: 10}, (_, index) => {
    const privacyStatus = index < 5 ? previous : current;
    return {
      period_key: index < 5 ? "previous" : "current",
      interest_level: index % 5,
      cell_order: index,
      value_count: privacyStatus === "displayed" ? 10 + index : null,
      privacy_status: privacyStatus,
    };
  });
}

const protectedReport = {
  report_id: "contact_sessions_by_interest_level_two_periods",
  report_version: 1,
  metric_id: "interest_distribution",
  metric_version: 1,
  statistical_unit: "contact_session",
  dimension: "interest_level",
  query_fingerprint:
    "management-report:contact_sessions_by_interest_level_two_periods:v1",
  privacy_policy: "management_interest_distribution_privacy_v1",
  source_scope: "backend_accepted_active_contacts_current_revision",
  project_id: projectId,
  periods,
  cells: cells(),
};

function completed(report: unknown = protectedReport) {
  return {
    access_contract_id:
      "authorized_interest_management_report_snapshot_read_v1",
    access_event_id: accessEventId,
    requested_snapshot_id: snapshotId,
    resolved_snapshot_id: snapshotId,
    result_status: "completed",
    reason_code: null,
    protected_report: report,
  };
}

function storeFor(accessResult: unknown) {
  return new PostgresManagementInterestReportSnapshotStore(async () => ({
    rows: [{access_result: accessResult}],
  }));
}

test("adapter calls only the interest runtime bridge once", async () => {
  const calls: Array<{
    readonly text: string;
    readonly values: readonly unknown[];
  }> = [];
  const store = new PostgresManagementInterestReportSnapshotStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{access_result: completed()}]};
    },
  );

  const result = await store.read(identity, projectId, snapshotId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.read_authorized_management_interest_report_snapshot_v1/,
  );
  assert.doesNotMatch(
    calls[0]?.text ?? "",
    /BEGIN|COMMIT|app_private|current_city|read_authorized_management_report_snapshot_v1/i,
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

test("adapter preserves value-free not-found and untrusted outcomes", async () => {
  const outcomes = [
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

  for (const outcome of outcomes) {
    const result = await storeFor({
      access_contract_id:
        "authorized_interest_management_report_snapshot_read_v1",
      access_event_id: accessEventId,
      requested_snapshot_id: snapshotId,
      ...outcome,
    }).read(identity, projectId, snapshotId);
    assert.equal(result.status, outcome.result_status);
    assert.equal("protectedReport" in result, false);
  }
});

test("adapter rejects other report families and envelope drift", async () => {
  const invalidResults = [
    {
      ...completed(),
      access_contract_id: "authorized_management_report_snapshot_read_v1",
    },
    {...completed(), project_id: projectId},
    {...completed(), requested_snapshot_id: accessEventId},
    {...completed(), resolved_snapshot_id: accessEventId},
    {
      ...completed(),
      result_status: "not_found",
      reason_code: "snapshot_not_available",
      resolved_snapshot_id: null,
    },
  ];
  for (const result of invalidResults) {
    await assert.rejects(
      storeFor(result).read(identity, projectId, snapshotId),
      /invalid interest management report snapshot access result/,
    );
  }
});

test("adapter rejects drift in every fixed interest report layer", async () => {
  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    ["extra report field", {...protectedReport, raw_total: 20}],
    ["wrong project", {...protectedReport, project_id: otherProjectId}],
    ["wrong metric", {...protectedReport, metric_id: "contact_sessions"}],
    ["wrong unit", {...protectedReport, statistical_unit: "person"}],
    ["wrong dimension", {...protectedReport, dimension: "channel"}],
    [
      "period discontinuity",
      {
        ...protectedReport,
        periods: {
          ...periods,
          current_period: {
            ...periods.current_period,
            start_utc: "2026-06-09T00:00:00.000Z",
          },
        },
      },
    ],
    [
      "cell order drift",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 1 ? {...cell, cell_order: 2} : cell
        ),
      },
    ],
    [
      "interest level drift",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 4 ? {...cell, interest_level: 3} : cell
        ),
      },
    ],
    [
      "mixed period privacy",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 1
            ? {...cell, privacy_status: "suppressed", value_count: null}
            : cell
        ),
      },
    ],
    [
      "suppressed value restored",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 9 ? {...cell, value_count: 0} : cell
        ),
      },
    ],
    [
      "sensitive contributor",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 0 ? {...cell, contributor_key: "hidden-user"} : cell
        ),
      },
    ],
  ];

  for (const [name, report] of invalidReports) {
    await assert.rejects(
      storeFor(completed(report)).read(identity, projectId, snapshotId),
      /invalid interest management report snapshot access result/,
      name,
    );
  }
});

test("adapter accepts safe integer counts and both period-wide states", async () => {
  const report = {
    ...protectedReport,
    cells: cells("suppressed", "displayed").map((cell, index) =>
      index === 9 ? {...cell, value_count: Number.MAX_SAFE_INTEGER} : cell
    ),
  };
  const result = await storeFor(completed(report)).read(
    identity,
    projectId,
    snapshotId,
  );
  assert.equal(result.status, "completed");
});

test("adapter maps only database authorization and hides its message", async () => {
  const forbidden = new PostgresManagementInterestReportSnapshotStore(
    async () => {
      throw Object.assign(new Error("private interest grant detail"), {
        code: "42501",
      });
    },
  );
  await assert.rejects(
    forbidden.read(identity, projectId, snapshotId),
    (error: unknown) =>
      error instanceof ManagementInterestReportSnapshotStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("grant"),
  );

  const unexpected = new Error("database unavailable");
  const unavailable = new PostgresManagementInterestReportSnapshotStore(
    async () => {
      throw unexpected;
    },
  );
  await assert.rejects(
    unavailable.read(identity, projectId, snapshotId),
    (error: unknown) => error === unexpected,
  );
});

test("adapter requires one named database result row", async () => {
  const invalidRows = [
    [],
    [{access_result: completed()}, {access_result: completed()}],
  ];
  for (const rows of invalidRows) {
    const store = new PostgresManagementInterestReportSnapshotStore(
      async () => ({rows}),
    );
    await assert.rejects(
      store.read(identity, projectId, snapshotId),
      /invalid interest management report snapshot access result/,
    );
  }
  const missingField = new PostgresManagementInterestReportSnapshotStore(
    async () => ({rows: [{}]}),
  );
  await assert.rejects(
    missingField.read(identity, projectId, snapshotId),
    /invalid interest management report snapshot access result/,
  );
});
