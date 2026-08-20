import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementCurrentCityReportSnapshotStoreError,
  readManagementCurrentCityReportSnapshot,
  type ManagementCurrentCityReportSnapshotRead,
} from "../src/management-current-city-report-snapshots.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const snapshotId = "88888888-8888-4888-8888-888888888888";
const accessEventId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const report = {
  report_id: "contact_sessions_by_current_city_two_periods",
  report_version: 1,
  cells: [{
    period_key: "current",
    city_id: "fixture-city",
    cell_order: 0,
    privacy_status: "suppressed",
    value_count: null,
  }],
};

function request(overrides: Partial<{
  authorization: string | undefined;
  projectId: string;
  snapshotId: string;
  hasQuery: boolean;
  hasBody: boolean;
}> = {}) {
  return {
    authorization: "Bearer token",
    projectId,
    snapshotId,
    hasQuery: false,
    hasBody: false,
    ...overrides,
  };
}

function completed(): ManagementCurrentCityReportSnapshotRead {
  return {
    status: "completed",
    accessEventId,
    requestedSnapshotId: snapshotId,
    resolvedSnapshotId: snapshotId,
    protectedReport: report,
  };
}

test("current-city HTTP handler authenticates before request validation or storage", async () => {
  let verifyCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {
      verify: async () => {
        verifyCalls += 1;
        return identity;
      },
    },
    snapshotStore: {
      read: async () => {
        storeCalls += 1;
        throw new Error("storage must not run");
      },
    },
  };

  assert.deepEqual(
    await readManagementCurrentCityReportSnapshot(
      request({authorization: undefined, projectId: "not-a-uuid"}),
      dependencies,
    ),
    {status: 401, body: {error: {code: "unauthenticated"}}},
  );
  assert.equal(verifyCalls, 0);

  assert.deepEqual(
    await readManagementCurrentCityReportSnapshot(
      request({projectId: "not-a-uuid", hasQuery: true, hasBody: true}),
      dependencies,
    ),
    {
      status: 400,
      body: {error: {code: "invalid_management_current_city_report_snapshot_request"}},
    },
  );
  assert.equal(verifyCalls, 1);
  assert.equal(storeCalls, 0);
});

test("invalid bearer is rejected before invalid IDs, body, or query", async () => {
  let storeCalls = 0;
  const result = await readManagementCurrentCityReportSnapshot(
    request({
      authorization: "Bearer invalid-token",
      projectId: "not-a-uuid",
      snapshotId: "also-not-a-uuid",
      hasQuery: true,
      hasBody: true,
    }),
    {
      identityVerifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      snapshotStore: {
        read: async () => {
          storeCalls += 1;
          throw new Error("storage must not run");
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

test("current-city HTTP handler rejects invalid IDs, query, and body without storage", async () => {
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {verify: async () => identity},
    snapshotStore: {
      read: async () => {
        storeCalls += 1;
        return completed();
      },
    },
  };

  for (const invalid of [
    request({projectId: "not-a-uuid"}),
    request({snapshotId: "not-a-uuid"}),
    request({hasQuery: true}),
    request({hasBody: true}),
  ]) {
    const result = await readManagementCurrentCityReportSnapshot(
      invalid,
      dependencies,
    );
    assert.deepEqual(result, {
      status: 400,
      body: {error: {code: "invalid_management_current_city_report_snapshot_request"}},
    });
  }
  assert.equal(storeCalls, 0);
});

test("current-city HTTP handler waits for the adapter and preserves the fixed report response", async () => {
  let finishRead: (() => void) | undefined;
  const readGate = new Promise<void>((resolve) => {finishRead = resolve;});
  const resultPromise = readManagementCurrentCityReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async (receivedIdentity, receivedProjectId, receivedSnapshotId) => {
          assert.deepEqual(receivedIdentity, identity);
          assert.equal(receivedProjectId, projectId);
          assert.equal(receivedSnapshotId, snapshotId);
          await readGate;
          return completed();
        },
      },
    },
  );
  let settled = false;
  void resultPromise.then(() => {settled = true;});
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(settled, false);
  finishRead?.();

  assert.deepEqual(await resultPromise, {
    status: 200,
    body: {
      access_event_id: accessEventId,
      snapshot_id: snapshotId,
      report,
    },
  });
});

test("current-city HTTP handler maps typed outcomes and hides unknown database errors", async () => {
  const outcomes: ReadonlyArray<{
    readonly stored: ManagementCurrentCityReportSnapshotRead;
    readonly status: number;
    readonly code: string;
  }> = [
    {
      stored: {
        status: "not_found",
        accessEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: null,
      },
      status: 404,
      code: "management_current_city_report_snapshot_not_found",
    },
    {
      stored: {
        status: "untrusted_provenance",
        accessEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: snapshotId,
      },
      status: 409,
      code: "management_current_city_report_snapshot_untrusted",
    },
  ];

  for (const outcome of outcomes) {
    const result = await readManagementCurrentCityReportSnapshot(
      request(),
      {
        identityVerifier: {verify: async () => identity},
        snapshotStore: {read: async () => outcome.stored},
      },
    );
    assert.deepEqual(result, {
      status: outcome.status,
      body: {error: {code: outcome.code, access_event_id: accessEventId}},
    });
  }

  const forbidden = await readManagementCurrentCityReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw new ManagementCurrentCityReportSnapshotStoreError("forbidden");
        },
      },
    },
  );
  assert.deepEqual(forbidden, {
    status: 403,
    body: {error: {code: "management_current_city_report_snapshot_forbidden"}},
  });

  const unknown = await readManagementCurrentCityReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw Object.assign(
            new Error("secret SQLSTATE 22P02 and subject management-viewer"),
            {code: "22P02"},
          );
        },
      },
    },
  );
  assert.deepEqual(unknown, {
    status: 503,
    body: {error: {code: "management_current_city_report_snapshot_unavailable"}},
  });
  assert.doesNotMatch(JSON.stringify(unknown), /22P02|secret|management-viewer/);
});

test("current-city HTTP handler maps verifier and absent adapter failures stably", async () => {
  const invalidIdentity = await readManagementCurrentCityReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => {throw new IdentityVerificationError();}},
      snapshotStore: {read: async () => completed()},
    },
  );
  assert.deepEqual(invalidIdentity, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });

  const verifierUnavailable = await readManagementCurrentCityReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => {throw new Error("jwks secret");}},
      snapshotStore: {read: async () => completed()},
    },
  );
  assert.deepEqual(verifierUnavailable, {
    status: 503,
    body: {error: {code: "management_current_city_report_snapshot_unavailable"}},
  });
  assert.doesNotMatch(JSON.stringify(verifierUnavailable), /jwks|secret/);

  const missingStore = await readManagementCurrentCityReportSnapshot(
    request(),
    {identityVerifier: {verify: async () => identity}},
  );
  assert.deepEqual(missingStore, {
    status: 503,
    body: {error: {code: "management_current_city_report_snapshot_unavailable"}},
  });
});
