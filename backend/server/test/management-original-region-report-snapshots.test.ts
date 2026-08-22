import assert from "node:assert/strict";
import test from "node:test";

import {
  ManagementOriginalRegionReportSnapshotStoreError,
  PostgresManagementOriginalRegionReportSnapshotStore,
} from "../src/management-original-region-report-snapshots.js";

const identity = {
  issuer: "https://runtime-original-region.synthetic/auth/v1",
  subject: "view-only-member",
};
const projectId = "6c130000-0000-4000-8000-000000000001";
const otherProjectId = "6c130000-0000-4000-8000-000000000002";
const snapshotId = "6ca00000-0000-4000-8000-000000000001";
const accessEventId = "6cd00000-0000-4000-8000-000000000001";

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

const sourceTreeContext = {
  source_tree_context_contract_id: "management-original-region-source-tree:v1",
  result_status: "selected",
  reason_code: "single_original_source_tree",
  source_tree_version: "fixture-original-region-v1",
  source_content_fingerprint: "a".repeat(64),
};

function cells(
  previous: "displayed" | "suppressed" = "displayed",
  current: "displayed" | "suppressed" = "suppressed",
) {
  const cityIds = ["city-a", "city-b"];
  return cityIds.flatMap((cityId, cityIndex) => [
    {
      period_key: "previous",
      city_id: cityId,
      cell_order: cityIndex,
      value_count: previous === "displayed" ? 10 + cityIndex : null,
      privacy_status: previous,
    },
    {
      period_key: "current",
      city_id: cityId,
      cell_order: cityIndex + cityIds.length,
      value_count: current === "displayed" ? 20 + cityIndex : null,
      privacy_status: current,
    },
  ]).sort((left, right) => left.cell_order - right.cell_order);
}

const protectedReport = {
  report_id: "contact_sessions_by_original_region_two_periods",
  report_version: 1,
  metric_id: "contact_sessions",
  metric_version: 1,
  dimension: "original_region",
  view_mode: "original",
  region_granularity: "city",
  query_fingerprint:
    "management-report:contact_sessions_by_original_region_two_periods:v1",
  privacy_policy: "management_original_region_contact_session_privacy_v1",
  source_scope: "backend_accepted_active_contacts_original_current_revision",
  project_id: projectId,
  periods,
  data_cutoff_utc: periods.data_cutoff_utc,
  source_change_sequence: 0,
  source_tree_context: sourceTreeContext,
  result_status: "completed",
  cells: cells(),
};

function completed(report: unknown = protectedReport) {
  return {
    access_contract_id:
      "authorized_original_region_management_report_snapshot_read_v1",
    access_event_id: accessEventId,
    requested_snapshot_id: snapshotId,
    resolved_snapshot_id: snapshotId,
    result_status: "completed",
    reason_code: null,
    protected_report: report,
  };
}

function withoutKey(
  value: Readonly<Record<string, unknown>>,
  keyToRemove: string,
): Readonly<Record<string, unknown>> {
  return Object.fromEntries(
    Object.entries(value).filter(([key]) => key !== keyToRemove),
  );
}

function storeFor(accessResult: unknown) {
  return new PostgresManagementOriginalRegionReportSnapshotStore(
    async () => ({rows: [{access_result: accessResult}]}),
  );
}

test("adapter calls only the original-region runtime bridge once", async () => {
  const calls: Array<{
    readonly text: string;
    readonly values: readonly unknown[];
  }> = [];
  const store = new PostgresManagementOriginalRegionReportSnapshotStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{access_result: completed()}]};
    },
  );

  const result = await store.read(identity, projectId, snapshotId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.read_authorized_management_original_region_report_snapshot_v1/,
  );
  assert.doesNotMatch(
    calls[0]?.text ?? "",
    /BEGIN|COMMIT|app_private|current_city|interest|channel|read_authorized_management_report_snapshot_v1/i,
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
        "authorized_original_region_management_report_snapshot_read_v1",
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
    withoutKey(completed(), "access_event_id"),
    withoutKey(completed(), "reason_code"),
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
      /invalid original-region management report snapshot access result/,
    );
  }
});

test("adapter rejects drift in every fixed original-region report layer", async () => {
  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    ["extra report field", {...protectedReport, raw_total: 20}],
    ["missing report field", withoutKey(protectedReport, "cells")],
    ["wrong project", {...protectedReport, project_id: otherProjectId}],
    [
      "channel report family",
      {...protectedReport, report_id: "contact_sessions_by_channel_two_periods"},
    ],
    [
      "current-city report family",
      {
        ...protectedReport,
        report_id: "contact_sessions_by_current_city_two_periods",
      },
    ],
    [
      "interest report family",
      {
        ...protectedReport,
        report_id: "contact_sessions_by_interest_level_two_periods",
      },
    ],
    ["wrong view", {...protectedReport, view_mode: "current"}],
    [
      "wrong source scope",
      {...protectedReport, source_scope: "backend_accepted_active_contacts"},
    ],
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
      "top-level and period cutoff mismatch",
      {
        ...protectedReport,
        data_cutoff_utc: "2026-06-17T12:34:57.000Z",
      },
    ],
    [
      "invalid reporting time zone",
      {
        ...protectedReport,
        periods: {...periods, reporting_time_zone: "Not/AZone"},
      },
    ],
    [
      "period extra field",
      {
        ...protectedReport,
        periods: {...periods, period_extra: true},
      },
    ],
    [
      "source tree contract drift",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          source_tree_context_contract_id: "management-region-target-context:v1",
        },
      },
    ],
    [
      "source tree result drift",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          result_status: "unavailable",
        },
      },
    ],
    [
      "source tree reason drift",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          reason_code: "multiple_source_trees",
        },
      },
    ],
    [
      "source tree version drift",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          source_tree_version: "",
        },
      },
    ],
    [
      "source tree version exceeds the contract limit",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          source_tree_version: "v".repeat(201),
        },
      },
    ],
    [
      "source tree fingerprint drift",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          source_content_fingerprint: "not-a-fingerprint",
        },
      },
    ],
    [
      "source tree extra field",
      {
        ...protectedReport,
        source_tree_context: {
          ...sourceTreeContext,
          source_record: "hidden",
        },
      },
    ],
    [
      "negative source sequence",
      {...protectedReport, source_change_sequence: -1},
    ],
    [
      "unsafe source sequence",
      {
        ...protectedReport,
        source_change_sequence: Number.MAX_SAFE_INTEGER + 1,
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
      "repeated city",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 1 ? {...cell, city_id: "city-a"} : cell
        ),
      },
    ],
    [
      "reverse city order",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 0
            ? {...cell, city_id: "city-b"}
            : index === 1
              ? {...cell, city_id: "city-a"}
              : index === 2
                ? {...cell, city_id: "city-b"}
                : index === 3
                  ? {...cell, city_id: "city-a"}
                  : cell
        ),
      },
    ],
    [
      "city set drift",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 3 ? {...cell, city_id: "city-c"} : cell
        ),
      },
    ],
    [
      "missing city period",
      {...protectedReport, cells: cells().slice(0, 3)},
    ],
    ["odd grid", {...protectedReport, cells: cells().slice(0, 3)}],
    ["empty grid", {...protectedReport, cells: []}],
    [
      "displayed count below threshold",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 0 ? {...cell, value_count: 9} : cell
        ),
      },
    ],
    [
      "displayed count outside safe integer range",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 0 ? {...cell, value_count: Number.MAX_SAFE_INTEGER + 1} : cell
        ),
      },
    ],
    [
      "suppressed count is not null",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 2 ? {...cell, value_count: 0} : cell
        ),
      },
    ],
    [
      "city name attached to a cell",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 0 ? {...cell, city_name: "Chicago"} : cell
        ),
      },
    ],
    [
      "coordinate attached to a cell",
      {
        ...protectedReport,
        cells: cells().map((cell, index) =>
          index === 0 ? {...cell, coordinates: [41.8, -87.6]} : cell
        ),
      },
    ],
    [
      "contributor attached to a cell",
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
      /invalid original-region management report snapshot access result/,
      name,
    );
  }
});

test("adapter accepts a full grid with safe counts and either period state", async () => {
  const report = {
    ...protectedReport,
    cells: cells("suppressed", "displayed").map((cell, index) =>
      index === 3 ? {...cell, value_count: Number.MAX_SAFE_INTEGER} : cell
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
  const forbidden = new PostgresManagementOriginalRegionReportSnapshotStore(
    async () => {
      throw Object.assign(new Error("private original-region grant detail"), {
        code: "42501",
      });
    },
  );
  await assert.rejects(
    forbidden.read(identity, projectId, snapshotId),
    (error: unknown) =>
      error instanceof ManagementOriginalRegionReportSnapshotStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("grant"),
  );

  const unexpected = new Error("database unavailable");
  const unavailable = new PostgresManagementOriginalRegionReportSnapshotStore(
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
    const store = new PostgresManagementOriginalRegionReportSnapshotStore(
      async () => ({rows}),
    );
    await assert.rejects(
      store.read(identity, projectId, snapshotId),
      /invalid original-region management report snapshot access result/,
    );
  }
  const missingField = new PostgresManagementOriginalRegionReportSnapshotStore(
    async () => ({rows: [{}]}),
  );
  await assert.rejects(
    missingField.read(identity, projectId, snapshotId),
    /invalid original-region management report snapshot access result/,
  );
});
