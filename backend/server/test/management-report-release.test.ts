import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementReportReleaseStoreError,
  PostgresManagementReportReleaseStore,
  releaseManagementReportSnapshot,
  type ManagementReportReleaseResult,
} from "../src/management-report-release.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const releaseRequestId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const comparedSnapshotId = "77777777-7777-4777-8777-777777777777";
const releasedSnapshotId = "88888888-8888-4888-8888-888888888888";
const baseReleaseResult: ManagementReportReleaseResult = {
  releaseContractId: "trusted_management_report_snapshot_release_v2",
  releaseRequestId,
  projectId,
  releaseLineageId:
    "management-report:contact_sessions_by_channel_two_periods",
  reportId: "contact_sessions_by_channel_two_periods",
  reportVersion: 1,
  queryFingerprint:
    "management-report:contact_sessions_by_channel_two_periods:v1",
  reportingTimeZoneVersionNumber: 2,
  reportingTimeZone: "America/Chicago",
  dataCutoffUtc: "2026-08-10T05:00:00.000Z",
  comparedSnapshotId,
  releasedSnapshotId,
  resultStatus: "approved",
  reasonCodes: [],
};

test("authenticated release returns the value-free fixed report result", async () => {
  const events: string[] = [];
  const result = await releaseManagementReportSnapshot(
    {
      authorization: "Bearer token",
      projectId,
      hasQuery: false,
      readBody: async () => {
        events.push("body");
        return {release_request_id: releaseRequestId};
      },
    },
    {
      identityVerifier: {
        verify: async () => {
          events.push("identity");
          return identity;
        },
      },
      releaseStore: {
        release: async (...values) => {
          events.push("store");
          assert.deepEqual(values, [identity, projectId, releaseRequestId]);
          return baseReleaseResult;
        },
      },
    },
  );

  assert.deepEqual(events, ["identity", "body", "store"]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      release_contract_id: "trusted_management_report_snapshot_release_v2",
      release_request_id: releaseRequestId,
      project_id: projectId,
      release_lineage_id:
        "management-report:contact_sessions_by_channel_two_periods",
      report_id: "contact_sessions_by_channel_two_periods",
      report_version: 1,
      query_fingerprint:
        "management-report:contact_sessions_by_channel_two_periods:v1",
      reporting_time_zone_version_number: 2,
      reporting_time_zone: "America/Chicago",
      data_cutoff_utc: "2026-08-10T05:00:00.000Z",
      compared_snapshot_id: comparedSnapshotId,
      released_snapshot_id: releasedSnapshotId,
      result_status: "approved",
      reason_codes: [],
    },
  });
  assert.doesNotMatch(
    JSON.stringify(result),
    /protected_report|cells|contributor|capability|membership|subject/,
  );
});

test("unauthenticated requests do not read the body or call the store", async () => {
  let bodyCalls = 0;
  let identityCalls = 0;
  let storeCalls = 0;
  const result = await releaseManagementReportSnapshot(
    {
      authorization: undefined,
      projectId: "not-a-uuid",
      hasQuery: true,
      readBody: async () => {
        bodyCalls += 1;
        return {release_request_id: "not-a-uuid"};
      },
    },
    {
      identityVerifier: {
        verify: async () => {
          identityCalls += 1;
          return identity;
        },
      },
      releaseStore: {
        release: async () => {
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
  assert.equal(bodyCalls, 0);
  assert.equal(identityCalls, 0);
  assert.equal(storeCalls, 0);
});

test("invalid identity returns 401 before request validation or body parsing", async () => {
  let bodyCalls = 0;
  const result = await releaseManagementReportSnapshot(
    {
      authorization: "Bearer invalid-token",
      projectId: "not-a-uuid",
      hasQuery: true,
      readBody: async () => {
        bodyCalls += 1;
        return {};
      },
    },
    {
      identityVerifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      releaseStore: undefined,
    },
  );

  assert.deepEqual(result, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(bodyCalls, 0);
});

test("strict path, query, and body validation follows authentication", async () => {
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {verify: async () => identity},
    releaseStore: {
      release: async () => {
        storeCalls += 1;
        return baseReleaseResult;
      },
    },
  };
  const baseRequest = {
    authorization: "Bearer token",
    projectId,
    hasQuery: false,
  };
  const requests = [
    {
      ...baseRequest,
      projectId: "not-a-uuid",
      readBody: async () => ({release_request_id: releaseRequestId}),
    },
    {
      ...baseRequest,
      hasQuery: true,
      readBody: async () => ({release_request_id: releaseRequestId}),
    },
    {...baseRequest, readBody: async () => ({})},
    {
      ...baseRequest,
      readBody: async () => ({release_request_id: releaseRequestId, extra: true}),
    },
    {
      ...baseRequest,
      readBody: async () => ({release_request_id: "not-a-uuid"}),
    },
    {...baseRequest, readBody: async () => []},
    {...baseRequest, readBody: async () => null},
  ];

  for (const request of requests) {
    const result = await releaseManagementReportSnapshot(request, dependencies);
    assert.deepEqual(result, {
      status: 400,
      body: {error: {code: "invalid_management_report_release_request"}},
    });
  }
  assert.equal(storeCalls, 0);
});

test("missing release dependency returns 503 after authentication and route checks", async () => {
  let bodyCalls = 0;
  const result = await releaseManagementReportSnapshot(
    {
      authorization: "Bearer token",
      projectId,
      hasQuery: false,
      readBody: async () => {
        bodyCalls += 1;
        return {release_request_id: releaseRequestId};
      },
    },
    {identityVerifier: {verify: async () => identity}, releaseStore: undefined},
  );

  assert.deepEqual(result, {
    status: 503,
    body: {error: {code: "management_report_release_unavailable"}},
  });
  assert.equal(bodyCalls, 0);
});

test("typed database outcomes map to stable value-free HTTP errors", async () => {
  for (const value of [
    {
      error: new ManagementReportReleaseStoreError("forbidden"),
      status: 403,
      code: "management_report_release_forbidden",
    },
    {
      error: new ManagementReportReleaseStoreError("conflict"),
      status: 409,
      code: "management_report_release_conflict",
    },
    {
      error: new Error("secret PostgreSQL detail"),
      status: 503,
      code: "management_report_release_unavailable",
    },
  ]) {
    const result = await releaseManagementReportSnapshot(
      {
        authorization: "Bearer token",
        projectId,
        hasQuery: false,
        readBody: async () => ({release_request_id: releaseRequestId}),
      },
      {
        identityVerifier: {verify: async () => identity},
        releaseStore: {release: async () => {throw value.error;}},
      },
    );
    assert.deepEqual(result, {
      status: value.status,
      body: {error: {code: value.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|PostgreSQL/);
  }
});

test("Postgres store calls one narrow bridge with verified identity and fixed UUIDs", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementReportReleaseStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{release_result: releaseDocument(baseReleaseResult)}]};
    },
  );

  const result = await store.release(identity, projectId, releaseRequestId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.release_management_report_snapshot_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [
    identity.issuer,
    identity.subject,
    releaseRequestId,
    projectId,
  ]);
  assert.deepEqual(result, baseReleaseResult);
});

test("Postgres parser accepts each value-free business status", async () => {
  const cases: readonly ManagementReportReleaseResult[] = [
    {
      ...baseReleaseResult,
      comparedSnapshotId: null,
      releasedSnapshotId,
      resultStatus: "approved_baseline",
      reasonCodes: [],
    },
    baseReleaseResult,
    {
      ...baseReleaseResult,
      releasedSnapshotId: null,
      resultStatus: "blocked",
      reasonCodes: ["release_time_zone_revision_changed"],
    },
  ];

  for (const expected of cases) {
    const store = new PostgresManagementReportReleaseStore(
      async () => ({rows: [{release_result: releaseDocument(expected)}]}),
    );
    assert.deepEqual(
      await store.release(identity, projectId, releaseRequestId),
      expected,
    );
  }
});

test("Postgres parser rejects malformed, extra, or value-bearing contracts", async () => {
  const valid = releaseDocument(baseReleaseResult);
  const invalidDocuments = [
    {...valid, cells: []},
    {...valid, protected_report: {}},
    {...valid, internal_user_id: "secret"},
    {...valid, release_request_id: "not-a-uuid"},
    {...valid, project_id: "44444444-4444-4444-8444-444444444444"},
    {...valid, report_version: 2},
    {...valid, reporting_time_zone: "not-a-zone"},
    {...valid, data_cutoff_utc: "not-a-time"},
    {...valid, data_cutoff_utc: "2026-02-31T00:00:00.000Z"},
    {...valid, data_cutoff_utc: "2026-08-10T00:00:00+00:00"},
    {...valid, result_status: "unknown"},
    {...valid, reason_codes: "blocked"},
    {...valid, reason_codes: ["unknown_release_reason"]},
    {
      ...valid,
      reason_codes: [
        "release_time_zone_revision_changed",
        "release_time_zone_revision_changed",
      ],
    },
    {...valid, compared_snapshot_id: null},
    {...valid, released_snapshot_id: null},
  ];

  for (const document of invalidDocuments) {
    const store = new PostgresManagementReportReleaseStore(
      async () => ({rows: [{release_result: document}]}),
    );
    await assert.rejects(
      store.release(identity, projectId, releaseRequestId),
      /invalid management report release result/,
    );
  }
});

test("Postgres store maps typed database codes without exposing messages", async () => {
  for (const [code, expected] of [
    ["42501", "forbidden"],
    ["22023", "conflict"],
    ["23505", "conflict"],
    ["55000", "conflict"],
  ] as const) {
    const databaseError = Object.assign(
      new Error("private database message"),
      {code},
    );
    const store = new PostgresManagementReportReleaseStore(
      async () => {throw databaseError;},
    );
    await assert.rejects(
      store.release(identity, projectId, releaseRequestId),
      (error: unknown) =>
        error instanceof ManagementReportReleaseStoreError &&
        error.code === expected &&
        !error.message.includes("private database"),
    );
  }
});

function releaseDocument(
  result: ManagementReportReleaseResult,
): Readonly<Record<string, unknown>> {
  return {
    release_contract_id: result.releaseContractId,
    release_request_id: result.releaseRequestId,
    project_id: result.projectId,
    release_lineage_id: result.releaseLineageId,
    report_id: result.reportId,
    report_version: result.reportVersion,
    query_fingerprint: result.queryFingerprint,
    reporting_time_zone_version_number: result.reportingTimeZoneVersionNumber,
    reporting_time_zone: result.reportingTimeZone,
    data_cutoff_utc: result.dataCutoffUtc,
    compared_snapshot_id: result.comparedSnapshotId,
    released_snapshot_id: result.releasedSnapshotId,
    result_status: result.resultStatus,
    reason_codes: result.reasonCodes,
  };
}
