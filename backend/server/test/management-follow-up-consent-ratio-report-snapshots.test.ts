import assert from "node:assert/strict";
import test from "node:test";

import {
  ManagementFollowUpConsentRatioReportSnapshotStoreError,
  PostgresManagementFollowUpConsentRatioReportSnapshotStore,
} from "../src/management-follow-up-consent-ratio-report-snapshots.js";

const identity = {
  issuer: "https://runtime-follow-up-consent-ratio.synthetic/auth/v1",
  subject: "view-only-member",
};
const projectId = "6e130000-0000-4000-8000-000000000001";
const otherProjectId = "6e130000-0000-4000-8000-000000000002";
const snapshotId = "6ea00000-0000-4000-8000-000000000001";
const accessEventId = "6ed00000-0000-4000-8000-000000000001";

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

function ratio(
  privacyStatus: "displayed" | "suppressed" = "displayed",
) {
  if (privacyStatus === "suppressed") {
    return {
      privacy_status: "suppressed",
      yes_count: null,
      no_count: null,
      numerator: null,
      denominator: null,
      percentage_basis_points: null,
    };
  }
  return {
    privacy_status: "displayed",
    yes_count: 20,
    no_count: 10,
    numerator: 20,
    denominator: 30,
    percentage_basis_points: 6667,
  };
}

function coverage(
  privacyStatus: "displayed" | "suppressed" = "suppressed",
  periodOrder = 0,
) {
  return ["unanswered", "refused", "not_applicable"].map(
    (consentState, index) => ({
      consent_state: consentState,
      cell_order: periodOrder * 3 + index,
      value_count: privacyStatus === "displayed" ? 10 + index : null,
      privacy_status: privacyStatus,
    }),
  );
}

function periodResults(
  previousRatio: "displayed" | "suppressed" = "displayed",
  currentRatio: "displayed" | "suppressed" = "suppressed",
) {
  return [
    {
      period_key: "previous",
      period_order: 0,
      ratio: ratio(previousRatio),
      coverage: coverage("suppressed"),
      unknown_count: 0,
      excluded_count: 0,
    },
    {
      period_key: "current",
      period_order: 1,
      ratio: ratio(currentRatio),
      coverage: coverage("displayed", 1),
      unknown_count: 0,
      excluded_count: 0,
    },
  ];
}

const protectedReport = {
  contract_id: "management_follow_up_consent_ratio_candidate_v1",
  report_id: "contact_target_follow_up_consent_ratio_two_periods",
  report_version: 1,
  metric_id: "follow_up_consent_ratio",
  metric_version: 1,
  statistical_unit: "contact_target_link",
  dimension: "consent_state",
  period_grain: "week",
  comparison_period_count: 2,
  period_boundary_id: "iso_week_monday_v1",
  privacy_policy: "management_follow_up_consent_ratio_privacy_v1",
  query_fingerprint:
    "management-report:contact_target_follow_up_consent_ratio_two_periods:v1",
  source_scope: "backend_accepted_active_contact_target_links_current_revision",
  project_id: projectId,
  status: "completed",
  periods,
  period_results: periodResults(),
};

function completed(report: unknown = protectedReport) {
  return {
    access_contract_id:
      "authorized_follow_up_consent_ratio_management_report_snapshot_read_v1",
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
  return new PostgresManagementFollowUpConsentRatioReportSnapshotStore(
    async () => ({rows: [{access_result: accessResult}]}),
  );
}

test("adapter calls only the four-argument runtime bridge once", async () => {
  const calls: Array<{
    readonly text: string;
    readonly values: readonly unknown[];
  }> = [];
  const store =
    new PostgresManagementFollowUpConsentRatioReportSnapshotStore(
      async (text: string, values: readonly unknown[]) => {
        calls.push({text, values});
        return {rows: [{access_result: completed()}]};
      },
    );

  const result = await store.read(identity, projectId, snapshotId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.read_authorized_management_follow_up_consent_report_snapshot_v1/,
  );
  assert.doesNotMatch(
    calls[0]?.text ?? "",
    /BEGIN|COMMIT|app_private|personal|current_city|interest|original|channel/i,
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
        "authorized_follow_up_consent_ratio_management_report_snapshot_read_v1",
      access_event_id: accessEventId,
      requested_snapshot_id: snapshotId,
      ...outcome,
    }).read(identity, projectId, snapshotId);
    assert.equal(result.status, outcome.result_status);
    assert.equal("protectedReport" in result, false);
  }
});

test("adapter rejects envelope and report-family drift", async () => {
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
      /invalid follow-up consent-ratio management report snapshot access result/,
    );
  }
});

test("adapter enforces all 17 protected-report root keys", async () => {
  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    ["extra root field", {...protectedReport, raw_total: 30}],
    ["missing root field", withoutKey(protectedReport, "period_results")],
    ["wrong project", {...protectedReport, project_id: otherProjectId}],
    ["wrong contract", {...protectedReport, contract_id: "other_v1"}],
    ["wrong report", {...protectedReport, report_id: "other_report"}],
    ["wrong metric", {...protectedReport, metric_id: "interest_distribution"}],
    ["wrong period count", {...protectedReport, comparison_period_count: 1}],
    ["wrong status", {...protectedReport, status: "not_enabled"}],
  ];

  for (const [name, report] of invalidReports) {
    await assert.rejects(
      storeFor(completed(report)).read(identity, projectId, snapshotId),
      /invalid follow-up consent-ratio management report snapshot access result/,
      name,
    );
  }

});

test("adapter enforces adjacent complete periods and two ordered results", async () => {
  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    [
      "one-hour periods are not complete ISO weeks",
      {
        ...protectedReport,
        periods: {
          ...periods,
          previous_period: {
            start_utc: "2026-06-08T22:00:00.000Z",
            until_utc: "2026-06-08T23:00:00.000Z",
          },
          current_period: {
            start_utc: "2026-06-08T23:00:00.000Z",
            until_utc: "2026-06-09T00:00:00.000Z",
          },
        },
      },
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
      "period result extra field",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0 ? {...period, hidden_total: 30} : period
        ),
      },
    ],
    [
      "period result order drift",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0 ? {...period, period_order: 1} : period
        ),
      },
    ],
    [
      "period key drift",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 1 ? {...period, period_key: "previous"} : period
        ),
      },
    ],
    [
      "missing period result",
      {...protectedReport, period_results: periodResults().slice(0, 1)},
    ],
    [
      "unknown count drift",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0 ? {...period, unknown_count: 1} : period
        ),
      },
    ],
    [
      "excluded count drift",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 1 ? {...period, excluded_count: 1} : period
        ),
      },
    ],
  ];

  for (const [name, report] of invalidReports) {
    await assert.rejects(
      storeFor(completed(report)).read(identity, projectId, snapshotId),
      /invalid follow-up consent-ratio management report snapshot access result/,
      name,
    );
  }

  const daylightSavingReport = {
    ...protectedReport,
    periods: {
      period_boundary_id: "iso_week_monday_v1",
      reporting_time_zone: "America/Chicago",
      data_cutoff_utc: "2026-03-18T12:00:00.000Z",
      previous_period: {
        start_utc: "2026-03-02T06:00:00.000Z",
        until_utc: "2026-03-09T05:00:00.000Z",
      },
      current_period: {
        start_utc: "2026-03-09T05:00:00.000Z",
        until_utc: "2026-03-16T05:00:00.000Z",
      },
    },
  };
  assert.equal(
    (await storeFor(completed(daylightSavingReport)).read(
      identity,
      projectId,
      snapshotId,
    )).status,
    "completed",
  );
});

test("adapter enforces ratio arithmetic, privacy nulls, and safe integers", async () => {
  const displayed = periodResults("displayed", "displayed");
  const validBoundary = {
    ...protectedReport,
    period_results: displayed.map((period, index) =>
      index === 1
        ? {
            ...period,
            ratio: {
              privacy_status: "displayed",
              yes_count: 10,
              no_count: Number.MAX_SAFE_INTEGER - 10,
              numerator: 10,
              denominator: Number.MAX_SAFE_INTEGER,
              percentage_basis_points: 0,
            },
          }
        : period
    ),
  };
  assert.equal(
    (await storeFor(completed(validBoundary)).read(
      identity,
      projectId,
      snapshotId,
    )).status,
    "completed",
  );

  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    [
      "suppressed ratio leaks count",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 1
            ? {
                ...period,
                ratio: {...ratio("suppressed"), yes_count: 10},
              }
            : period
        ),
      },
    ],
    [
      "displayed ratio below threshold",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {...period, ratio: {...ratio(), yes_count: 9}}
            : period
        ),
      },
    ],
    [
      "unsafe ratio count",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {
                ...period,
                ratio: {
                  ...ratio(),
                  no_count: Number.MAX_SAFE_INTEGER + 1,
                },
              }
            : period
        ),
      },
    ],
    [
      "numerator mismatch",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {...period, ratio: {...ratio(), numerator: 21}}
            : period
        ),
      },
    ],
    [
      "denominator mismatch",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {...period, ratio: {...ratio(), denominator: 31}}
            : period
        ),
      },
    ],
    [
      "percentage mismatch",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {...period, ratio: {...ratio(), percentage_basis_points: 6666}}
            : period
        ),
      },
    ],
    [
      "ratio extra key",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {...period, ratio: {...ratio(), total: 30}}
            : period
        ),
      },
    ],
  ];

  for (const [name, report] of invalidReports) {
    await assert.rejects(
      storeFor(completed(report)).read(identity, projectId, snapshotId),
      /invalid follow-up consent-ratio management report snapshot access result/,
      name,
    );
  }
});

test("adapter enforces ordered coverage cells, null suppression, and PII rejection", async () => {
  const invalidReports: ReadonlyArray<readonly [string, unknown]> = [
    [
      "coverage state drift",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {
                ...period,
                coverage: coverage().map((cell, cellIndex) =>
                  cellIndex === 0
                    ? {...cell, consent_state: "yes"}
                    : cell
                ),
              }
            : period
        ),
      },
    ],
    [
      "coverage order drift",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 1
            ? {
                ...period,
                coverage: coverage("displayed", 1).map((cell, cellIndex) =>
                  cellIndex === 0 ? {...cell, cell_order: 4} : cell
                ),
              }
            : period
        ),
      },
    ],
    [
      "suppressed coverage leaks count",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {
                ...period,
                coverage: coverage().map((cell, cellIndex) =>
                  cellIndex === 1 ? {...cell, value_count: 10} : cell
                ),
              }
            : period
        ),
      },
    ],
    [
      "displayed coverage below threshold",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 1
            ? {
                ...period,
                coverage: coverage("displayed", 1).map((cell, cellIndex) =>
                  cellIndex === 0 ? {...cell, value_count: 9} : cell
                ),
              }
            : period
        ),
      },
    ],
    [
      "coverage extra key",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 1
            ? {
                ...period,
                coverage: coverage("displayed", 1).map((cell, cellIndex) =>
                  cellIndex === 0 ? {...cell, target_id: "hidden"} : cell
                ),
              }
            : period
        ),
      },
    ],
    [
      "nested contact PII",
      {
        ...protectedReport,
        period_results: periodResults().map((period, index) =>
          index === 0
            ? {
                ...period,
                coverage: coverage().map((cell, cellIndex) =>
                  cellIndex === 0 ? {...cell, contact_id: "hidden"} : cell
                ),
              }
            : period
        ),
      },
    ],
  ];

  for (const [name, report] of invalidReports) {
    await assert.rejects(
      storeFor(completed(report)).read(identity, projectId, snapshotId),
      /invalid follow-up consent-ratio management report snapshot access result/,
      name,
    );
  }
});

test("adapter maps only SQLSTATE 42501 to forbidden", async () => {
  const forbidden =
    new PostgresManagementFollowUpConsentRatioReportSnapshotStore(
      async () => {
        throw Object.assign(new Error("private grant detail"), {
          code: "42501",
        });
      },
    );
  await assert.rejects(
    forbidden.read(identity, projectId, snapshotId),
    (error: unknown) => {
      if (
        !(error instanceof
          ManagementFollowUpConsentRatioReportSnapshotStoreError)
      ) {
        return false;
      }
      const typedError = error as {
        readonly code: unknown;
        readonly message: unknown;
      };
      return typedError.code === "forbidden" &&
        typeof typedError.message === "string" &&
        !typedError.message.includes("grant");
    },
  );

  const invalidInput = Object.assign(new Error("invalid input"), {
    code: "22023",
  });
  const invalid =
    new PostgresManagementFollowUpConsentRatioReportSnapshotStore(
      async () => {
        throw invalidInput;
      },
    );
  await assert.rejects(
    invalid.read(identity, projectId, snapshotId),
    (error: unknown) => error === invalidInput,
  );
});

test("adapter requires exactly one named database result row", async () => {
  for (const rows of [
    [],
    [{access_result: completed()}, {access_result: completed()}],
  ]) {
    const store =
      new PostgresManagementFollowUpConsentRatioReportSnapshotStore(
        async () => ({rows}),
      );
    await assert.rejects(
      store.read(identity, projectId, snapshotId),
      /invalid follow-up consent-ratio management report snapshot access result/,
    );
  }
  const missingField =
    new PostgresManagementFollowUpConsentRatioReportSnapshotStore(
      async () => ({rows: [{}]}),
    );
  await assert.rejects(
    missingField.read(identity, projectId, snapshotId),
    /invalid follow-up consent-ratio management report snapshot access result/,
  );
});
