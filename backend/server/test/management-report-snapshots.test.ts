import assert from "node:assert/strict";
import test from "node:test";

import {
  ManagementReportSnapshotStoreError,
  PostgresManagementReportSnapshotStore,
  readManagementReportSnapshot,
} from "../src/management-report-snapshots.js";
import {IdentityVerificationError} from "../src/identity.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const snapshotId = "88888888-8888-4888-8888-888888888888";
const accessEventId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const protectedReport = {
  report_id: "contact_sessions_by_channel_two_periods",
  report_version: 1,
  cells: [{privacy_status: "suppressed", value_count: null}],
};

test("verified identity reads one protected snapshot without SessionContext", async () => {
  let received: readonly unknown[] | undefined;
  const result = await readManagementReportSnapshot(
    "Bearer token",
    projectId,
    snapshotId,
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async (...values) => {
          received = values;
          return {
            status: "completed",
            accessEventId,
            requestedSnapshotId: snapshotId,
            resolvedSnapshotId: snapshotId,
            protectedReport,
          };
        },
      },
    },
  );

  assert.deepEqual(received, [identity, projectId, snapshotId]);
  assert.deepEqual(result, {
    status: 200,
    body: {
      access_event_id: accessEventId,
      snapshot_id: snapshotId,
      report: protectedReport,
    },
  });
});

test("management snapshot fails closed on nested exact location facts", async () => {
  const result = await readManagementReportSnapshot(
    "Bearer token",
    projectId,
    snapshotId,
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => ({
          status: "completed",
          accessEventId,
          requestedSnapshotId: snapshotId,
          resolvedSnapshotId: snapshotId,
          protectedReport: {
            ...protectedReport,
            cells: [{
              privacy_status: "suppressed",
              value_count: null,
              location_source: {latitude: 41.7897, longitude: -87.5997},
            }],
          },
        }),
      },
    },
  );

  assert.deepEqual(result, {
    status: 503,
    body: {error: {code: "management_report_snapshot_unavailable"}},
  });
  assert.doesNotMatch(JSON.stringify(result), /41\.7897|-87\.5997/);
});

test("missing bearer and invalid ids fail before the snapshot store", async () => {
  let identityCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {
      verify: async () => {
        identityCalls += 1;
        return identity;
      },
    },
    snapshotStore: {
      read: async () => {
        storeCalls += 1;
        throw new Error("store must not run");
      },
    },
  };

  assert.deepEqual(
    await readManagementReportSnapshot(undefined, projectId, snapshotId, dependencies),
    {status: 401, body: {error: {code: "unauthenticated"}}},
  );
  assert.deepEqual(
    await readManagementReportSnapshot("Bearer token", "not-a-uuid", snapshotId, dependencies),
    {
      status: 400,
      body: {error: {code: "invalid_management_report_snapshot_request"}},
    },
  );
  assert.equal(identityCalls, 0);
  assert.equal(storeCalls, 0);
});

test("invalid bearer returns 401 without calling the snapshot store", async () => {
  let storeCalls = 0;
  const result = await readManagementReportSnapshot(
    "Bearer invalid-token",
    projectId,
    snapshotId,
    {
      identityVerifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      snapshotStore: {
        read: async () => {
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
  assert.equal(storeCalls, 0);
});

test("typed database outcomes have stable value-free HTTP errors", async () => {
  const cases = [
    {
      stored: {
        status: "not_found" as const,
        accessEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: null,
      },
      expected: {
        status: 404,
        body: {
          error: {
            code: "management_report_snapshot_not_found",
            access_event_id: accessEventId,
          },
        },
      },
    },
    {
      stored: {
        status: "untrusted_provenance" as const,
        accessEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: snapshotId,
      },
      expected: {
        status: 409,
        body: {
          error: {
            code: "management_report_snapshot_untrusted",
            access_event_id: accessEventId,
          },
        },
      },
    },
  ];

  for (const value of cases) {
    const result = await readManagementReportSnapshot(
      "Bearer token",
      projectId,
      snapshotId,
      {
        identityVerifier: {verify: async () => identity},
        snapshotStore: {read: async () => value.stored},
      },
    );
    assert.deepEqual(result, value.expected);
    assert.doesNotMatch(JSON.stringify(result), /protected_report|cells/);
  }
});

test("authorization and contract failures do not expose PostgreSQL errors", async () => {
  for (const value of [
    {
      error: new ManagementReportSnapshotStoreError("forbidden"),
      status: 403,
      code: "management_report_snapshot_forbidden",
    },
    {
      error: new Error("secret database detail"),
      status: 503,
      code: "management_report_snapshot_unavailable",
    },
  ]) {
    const result = await readManagementReportSnapshot(
      "Bearer token",
      projectId,
      snapshotId,
      {
        identityVerifier: {verify: async () => identity},
        snapshotStore: {read: async () => {throw value.error;}},
      },
    );
    assert.deepEqual(result, {
      status: value.status,
      body: {error: {code: value.code}},
    });
    assert.doesNotMatch(JSON.stringify(result), /secret|PostgreSQL/);
  }
});

test("Postgres store calls the runtime bridge once with verified identity", async () => {
  const calls: Array<{
    readonly text: string;
    readonly values: readonly unknown[];
  }> = [];
  const store = new PostgresManagementReportSnapshotStore(
    async (text, values) => {
      calls.push({text, values});
      return {
        rows: [{
          access_result: {
            access_contract_id:
              "authorized_management_report_snapshot_read_v1",
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
    /app_data\.read_authorized_management_report_snapshot_v1/,
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
    accessEventId,
    requestedSnapshotId: snapshotId,
    resolvedSnapshotId: snapshotId,
    protectedReport,
  });
});

test("Postgres store rejects a malformed access contract", async () => {
  const store = new PostgresManagementReportSnapshotStore(async () => ({
    rows: [{access_result: {result_status: "completed"}}],
  }));

  await assert.rejects(
    store.read(identity, projectId, snapshotId),
    /invalid management report snapshot access result/,
  );
});

test("Postgres store maps database authorization without its message", async () => {
  const databaseError = Object.assign(
    new Error("management report authorization forbidden"),
    {code: "42501"},
  );
  const store = new PostgresManagementReportSnapshotStore(
    async () => {throw databaseError;},
  );

  await assert.rejects(
    store.read(identity, projectId, snapshotId),
    (error: unknown) =>
      error instanceof ManagementReportSnapshotStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("management report"),
  );
});
