import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementReportSnapshotExportStoreError,
  PostgresManagementReportSnapshotExportStore,
  exportManagementReportSnapshot,
} from "../src/management-report-snapshot-exports.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-exporter",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const snapshotId = "88888888-8888-4888-8888-888888888888";
const exportEventId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

test("verified identity exports one fixed snapshot without personal context", async () => {
  let received: readonly unknown[] | undefined;
  const result = await exportManagementReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      exportStore: {
        export: async (...values) => {
          received = values;
          return {
            status: "completed",
            exportEventId,
            requestedSnapshotId: snapshotId,
            resolvedSnapshotId: snapshotId,
            content: canonicalDocumentText(),
          };
        },
      },
    },
  );

  assert.deepEqual(received, [identity, projectId, snapshotId]);
  assert.deepEqual(result, {
    status: 200,
    exportEventId,
    content: canonicalDocumentText(),
  });
});

test("export authenticates before rejecting path fields or missing store", async () => {
  let storeCalls = 0;
  const unauthenticated = await exportManagementReportSnapshot(
    {...request(), projectId: "not-a-uuid", hasQuery: true, hasBody: true},
    {
      identityVerifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      exportStore: {
        export: async () => {
          storeCalls += 1;
          throw new Error("must not run");
        },
      },
    },
  );
  assert.deepEqual(unauthenticated, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });

  const invalid = await exportManagementReportSnapshot(
    {...request(), hasQuery: true},
    {identityVerifier: {verify: async () => identity}},
  );
  assert.deepEqual(invalid, {
    status: 400,
    body: {error: {code: "invalid_management_report_snapshot_export_request"}},
  });
  const unavailable = await exportManagementReportSnapshot(
    request(),
    {identityVerifier: {verify: async () => identity}},
  );
  assert.deepEqual(unavailable, {
    status: 503,
    body: {error: {code: "management_report_snapshot_export_unavailable"}},
  });
  assert.equal(storeCalls, 0);
});

test("typed database outcomes use stable value-free export errors", async () => {
  const cases = [
    {
      stored: {
        status: "not_found" as const,
        exportEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: null,
      },
      expected: {
        status: 404,
        body: {
          error: {
            code: "management_report_snapshot_export_not_found",
            export_event_id: exportEventId,
          },
        },
      },
    },
    {
      stored: {
        status: "untrusted_provenance" as const,
        exportEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: snapshotId,
      },
      expected: {
        status: 409,
        body: {
          error: {
            code: "management_report_snapshot_export_untrusted",
            export_event_id: exportEventId,
          },
        },
      },
    },
  ];

  for (const value of cases) {
    const result = await exportManagementReportSnapshot(request(), {
      identityVerifier: {verify: async () => identity},
      exportStore: {export: async () => value.stored},
    });
    assert.deepEqual(result, value.expected);
    assert.doesNotMatch(JSON.stringify(result), /"report"|cells|value_count/);
  }
});

test("store errors map to stable forbidden or unavailable responses", async () => {
  for (const value of [
    {
      error: new ManagementReportSnapshotExportStoreError("forbidden"),
      status: 403,
      code: "management_report_snapshot_export_forbidden",
    },
    {
      error: new Error("secret database detail"),
      status: 503,
      code: "management_report_snapshot_export_unavailable",
    },
  ]) {
    const result = await exportManagementReportSnapshot(request(), {
      identityVerifier: {verify: async () => identity},
      exportStore: {export: async () => {throw value.error;}},
    });
    assert.deepEqual(result, {
      status: value.status,
      body: {error: {code: value.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|PostgreSQL/);
  }
});

test("Postgres store calls only the narrow runtime export bridge", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementReportSnapshotExportStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{export_result: completedDatabaseResult()}]};
    },
  );

  const result = await store.export(identity, projectId, snapshotId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.export_authorized_management_report_snapshot_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /BEGIN|COMMIT|app_private/i);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    projectId,
    snapshotId,
  ]);
  assert.deepEqual(result, {
    status: "completed",
    exportEventId,
    requestedSnapshotId: snapshotId,
    resolvedSnapshotId: snapshotId,
    content: canonicalDocumentText(),
  });
});

test(
  "Postgres store rejects malformed export results and hides authorization details",
  async () => {
    const malformed = new PostgresManagementReportSnapshotExportStore(
      async () => ({rows: [{export_result: {result_status: "completed"}}]}),
    );
    await assert.rejects(
      malformed.export(identity, projectId, snapshotId),
      /invalid management report snapshot export result/,
    );

    const forbidden = new PostgresManagementReportSnapshotExportStore(
      async () => {
        throw Object.assign(new Error("private grant detail"), {code: "42501"});
      },
    );
    await assert.rejects(
      forbidden.export(identity, projectId, snapshotId),
      (error: unknown) =>
        error instanceof ManagementReportSnapshotExportStoreError &&
        error.code === "forbidden" &&
        !error.message.includes("grant"),
    );
  },
);

function request() {
  return {
    authorization: "Bearer token",
    projectId,
    snapshotId,
    hasQuery: false,
    hasBody: false,
  };
}

function completedDatabaseResult() {
  return {
    export_access_contract_id:
      "authorized_management_report_snapshot_export_v1",
    export_event_id: exportEventId,
    requested_snapshot_id: snapshotId,
    resolved_snapshot_id: snapshotId,
    result_status: "completed",
    reason_code: null,
    export_document: exportDocument(),
  };
}

function canonicalDocumentText() {
  return JSON.stringify(exportDocument());
}

function exportDocument() {
  return {
    export_contract_id: "management_report_snapshot_export_v1",
    snapshot_id: snapshotId,
    released_at_utc: "2030-01-15T12:34:56.789Z",
    report: {
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
        reporting_time_zone: "UTC",
        data_cutoff_utc: "2030-01-14T00:00:00.000Z",
        previous_period: {
          start_utc: "2029-12-31T00:00:00.000Z",
          until_utc: "2030-01-07T00:00:00.000Z",
        },
        current_period: {
          start_utc: "2030-01-07T00:00:00.000Z",
          until_utc: "2030-01-14T00:00:00.000Z",
        },
      },
      cells: exportCells(),
    },
  };
}

function exportCells() {
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
    categories.map((categoryKey, categoryIndex) => ({
      period_key: periodKey,
      category_key: categoryKey,
      cell_order: periodIndex * categories.length + categoryIndex,
      privacy_status: categoryKey === "all" ? "displayed" : "suppressed",
      value_count: categoryKey === "all" ? 10 : null,
    }))
  );
}
