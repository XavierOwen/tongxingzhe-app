import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementReportSnapshotDirectoryStoreError,
  PostgresManagementReportSnapshotDirectoryStore,
  listManagementReportSnapshotDirectory,
} from "../src/management-report-snapshot-directory.js";

const projectId = "33333333-3333-4333-8333-333333333333";
const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};

test("authorized member receives only bounded snapshot metadata", async () => {
  const result = await listManagementReportSnapshotDirectory(
    {
      authorization: "Bearer token",
      projectId,
      hasQuery: false,
      hasBody: false,
    },
    {
      identityVerifier: {verify: async () => identity},
      directoryStore: {
        list: async () => ({
          accessEventId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          projectId,
          snapshots: [{
            snapshotId: "88888888-8888-4888-8888-888888888888",
            reportId: "contact_sessions_by_channel_two_periods",
            reportVersion: 1,
            reportingTimeZone: "America/Chicago",
            dataCutoffUtc: "2026-08-10T05:00:00.000Z",
            releasedAtUtc: "2026-08-10T05:00:01.000Z",
          }],
        }),
      },
    },
  );

  assert.deepEqual(result, {
    status: 200,
    body: {
      access_event_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      project_id: projectId,
      snapshots: [{
        snapshot_id: "88888888-8888-4888-8888-888888888888",
        report_id: "contact_sessions_by_channel_two_periods",
        report_version: 1,
        reporting_time_zone: "America/Chicago",
        data_cutoff_utc: "2026-08-10T05:00:00.000Z",
        released_at_utc: "2026-08-10T05:00:01.000Z",
      }],
    },
  });
  assert.doesNotMatch(
    JSON.stringify(result),
    /protected_report|cells|contributor|membership|capability|subject/,
  );
});

test("Postgres store uses one narrow directory bridge", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementReportSnapshotDirectoryStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{directory_result: {
        access_contract_id: "authorized_management_report_snapshot_directory_v1",
        access_event_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        project_id: projectId,
        snapshots: [{
          snapshot_id: "88888888-8888-4888-8888-888888888888",
          report_id: "contact_sessions_by_channel_two_periods",
          report_version: 1,
          reporting_time_zone: "America/Chicago",
          data_cutoff_utc: "2026-08-10T00:00:00-05:00",
          released_at_utc: "2026-08-10T05:00:01+00:00",
        }],
      }}]};
    },
  );

  const result = await store.list(identity, projectId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.list_authorized_management_report_snapshots_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject, projectId]);
  assert.deepEqual(result, {
    accessEventId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    projectId,
    snapshots: [{
      snapshotId: "88888888-8888-4888-8888-888888888888",
      reportId: "contact_sessions_by_channel_two_periods",
      reportVersion: 1,
      reportingTimeZone: "America/Chicago",
      dataCutoffUtc: "2026-08-10T05:00:00.000Z",
      releasedAtUtc: "2026-08-10T05:00:01.000Z",
    }],
  });
});

test("missing or invalid authentication precedes request and store validation", async () => {
  let storeCalls = 0;
  let verificationCalls = 0;
  for (const authorization of [undefined, "Bearer invalid"]) {
    const result = await listManagementReportSnapshotDirectory(
      {
        authorization,
        projectId: "not-a-uuid",
        hasQuery: true,
        hasBody: true,
      },
      {
        identityVerifier: {
          verify: async () => {
            verificationCalls += 1;
            throw new IdentityVerificationError();
          },
        },
        directoryStore: {
          list: async () => {
            storeCalls += 1;
            throw new Error("store must not run");
          },
        },
      },
    );

    assert.deepEqual(result, {
      status: 401,
      body: {error: {code: "unauthenticated"}},
    });
  }
  assert.equal(verificationCalls, 1);
  assert.equal(storeCalls, 0);
});

test("request, authorization, and database failures stay distinct", async () => {
  const baseRequest = {
    authorization: "Bearer token",
    projectId,
    hasQuery: false,
    hasBody: false,
  };
  const identityVerifier = {verify: async () => identity};

  assert.deepEqual(
    await listManagementReportSnapshotDirectory(
      {...baseRequest, hasQuery: true},
      {identityVerifier, directoryStore: undefined},
    ),
    {
      status: 400,
      body: {error: {code: "invalid_management_report_snapshot_directory_request"}},
    },
  );
  assert.deepEqual(
    await listManagementReportSnapshotDirectory(
      baseRequest,
      {identityVerifier, directoryStore: undefined},
    ),
    {
      status: 503,
      body: {error: {code: "management_report_snapshot_directory_unavailable"}},
    },
  );
  for (const value of [
    {
      error: new ManagementReportSnapshotDirectoryStoreError("forbidden"),
      status: 403,
      code: "management_report_snapshot_directory_forbidden",
    },
    {
      error: new Error("secret database message"),
      status: 503,
      code: "management_report_snapshot_directory_unavailable",
    },
  ]) {
    const result = await listManagementReportSnapshotDirectory(
      baseRequest,
      {
        identityVerifier,
        directoryStore: {list: async () => {throw value.error;}},
      },
    );
    assert.deepEqual(result, {
      status: value.status,
      body: {error: {code: value.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|database/);
  }
});

test("Postgres parser rejects malformed or unstable directories", async () => {
  const validItem = {
    snapshot_id: "88888888-8888-4888-8888-888888888888",
    report_id: "contact_sessions_by_channel_two_periods",
    report_version: 1,
    reporting_time_zone: "UTC",
    data_cutoff_utc: "2026-08-10T05:00:00.000Z",
    released_at_utc: "2026-08-10T05:00:01.000Z",
  };
  const invalidDirectories = [
    {...directoryDocument([validItem]), internal_user_id: "secret"},
    directoryDocument(Array.from({length: 21}, (_, index) => ({
      ...validItem,
      snapshot_id: `88888888-8888-4888-8888-${String(index).padStart(12, "0")}`,
    }))),
    directoryDocument([validItem, validItem]),
    directoryDocument([
      validItem,
      {
        ...validItem,
        snapshot_id: "77777777-7777-4777-8777-777777777777",
        data_cutoff_utc: "2026-08-11T05:00:00.000Z",
        released_at_utc: "2026-08-11T05:00:01.000Z",
      },
    ]),
    directoryDocument([{...validItem, released_at_utc: "not-a-time"}]),
  ];

  for (const directory of invalidDirectories) {
    const store = new PostgresManagementReportSnapshotDirectoryStore(
      async () => ({rows: [{directory_result: directory}]}),
    );
    await assert.rejects(
      store.list(identity, projectId),
      /invalid management report snapshot directory result/,
    );
  }
});

function directoryDocument(snapshots: readonly unknown[]): Record<string, unknown> {
  return {
    access_contract_id: "authorized_management_report_snapshot_directory_v1",
    access_event_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    project_id: projectId,
    snapshots,
  };
}
