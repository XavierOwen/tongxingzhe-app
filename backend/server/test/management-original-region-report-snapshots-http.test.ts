import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementOriginalRegionReportSnapshotStoreError,
  readManagementOriginalRegionReportSnapshot,
  type ManagementOriginalRegionReportSnapshotRead,
} from "../src/management-original-region-report-snapshots.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-original-region-viewer",
};
const projectId = "6c130000-0000-4000-8000-000000000001";
const snapshotId = "6ca00000-0000-4000-8000-000000000001";
const accessEventId = "6cd00000-0000-4000-8000-000000000001";
const report = {
  report_id: "contact_sessions_by_original_region_two_periods",
  source_tree_context: {
    source_tree_version: "fixture-original-region-v1",
    source_content_fingerprint: "a".repeat(64),
  },
  cells: [],
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

function completed(): ManagementOriginalRegionReportSnapshotRead {
  return {
    status: "completed",
    accessEventId,
    requestedSnapshotId: snapshotId,
    resolvedSnapshotId: snapshotId,
    protectedReport: report,
  };
}

test("original-region HTTP handler authenticates before validation or storage", async () => {
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
    await readManagementOriginalRegionReportSnapshot(
      request({authorization: undefined, projectId: "not-a-uuid"}),
      dependencies,
    ),
    {status: 401, body: {error: {code: "unauthenticated"}}},
  );
  assert.equal(verifyCalls, 0);

  assert.deepEqual(
    await readManagementOriginalRegionReportSnapshot(
      request({projectId: "not-a-uuid", hasQuery: true, hasBody: true}),
      dependencies,
    ),
    {
      status: 400,
      body: {
        error: {
          code: "invalid_management_original_region_report_snapshot_request",
        },
      },
    },
  );
  assert.equal(verifyCalls, 1);
  assert.equal(storeCalls, 0);
});

test("invalid bearer is rejected before malformed resources or storage", async () => {
  let storeCalls = 0;
  const result = await readManagementOriginalRegionReportSnapshot(
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

test("original-region HTTP handler rejects invalid IDs, query, and body without storage", async () => {
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
    const result = await readManagementOriginalRegionReportSnapshot(
      invalid,
      dependencies,
    );
    assert.deepEqual(result, {
      status: 400,
      body: {
        error: {
          code: "invalid_management_original_region_report_snapshot_request",
        },
      },
    });
  }
  assert.equal(storeCalls, 0);
});

test("original-region HTTP handler waits for the adapter and preserves the report", async () => {
  let finishRead: (() => void) | undefined;
  const readGate = new Promise<void>((resolve) => {finishRead = resolve;});
  const resultPromise = readManagementOriginalRegionReportSnapshot(
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

test("original-region HTTP handler maps outcomes and hides database details", async () => {
  const outcomes: ReadonlyArray<{
    readonly stored: ManagementOriginalRegionReportSnapshotRead;
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
      code: "management_original_region_report_snapshot_not_found",
    },
    {
      stored: {
        status: "untrusted_provenance",
        accessEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: snapshotId,
      },
      status: 409,
      code: "management_original_region_report_snapshot_untrusted",
    },
  ];

  for (const outcome of outcomes) {
    const result = await readManagementOriginalRegionReportSnapshot(
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

  const forbidden = await readManagementOriginalRegionReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw new ManagementOriginalRegionReportSnapshotStoreError("forbidden");
        },
      },
    },
  );
  assert.deepEqual(forbidden, {
    status: 403,
    body: {
      error: {code: "management_original_region_report_snapshot_forbidden"},
    },
  });

  const unknown = await readManagementOriginalRegionReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw Object.assign(
            new Error(
              "secret SQLSTATE 22P02, subject management-original-region-viewer, " +
              "protected_report value_count source_tree_context",
            ),
            {code: "22P02"},
          );
        },
      },
    },
  );
  assert.deepEqual(unknown, {
    status: 503,
    body: {
      error: {
        code: "management_original_region_report_snapshot_unavailable",
      },
    },
  });
  assert.doesNotMatch(
    JSON.stringify(unknown),
    /22P02|secret|management-original-region-viewer|protected_report|value_count|source_tree_context/,
  );

  const parserFailure = await readManagementOriginalRegionReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw new Error(
            "invalid original-region management report snapshot access result: protected_report",
          );
        },
      },
    },
  );
  assert.deepEqual(parserFailure, {
    status: 503,
    body: {
      error: {
        code: "management_original_region_report_snapshot_unavailable",
      },
    },
  });
  assert.doesNotMatch(
    JSON.stringify(parserFailure),
    /invalid|access result|protected_report/,
  );
});

test("original-region HTTP handler maps verifier and absent store failures stably", async () => {
  const invalidIdentity = await readManagementOriginalRegionReportSnapshot(
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

  const verifierUnavailable = await readManagementOriginalRegionReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => {throw new Error("jwks secret");}},
      snapshotStore: {read: async () => completed()},
    },
  );
  assert.deepEqual(verifierUnavailable, {
    status: 503,
    body: {
      error: {
        code: "management_original_region_report_snapshot_unavailable",
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(verifierUnavailable), /jwks|secret/);

  const missingStore = await readManagementOriginalRegionReportSnapshot(
    request(),
    {identityVerifier: {verify: async () => identity}},
  );
  assert.deepEqual(missingStore, {
    status: 503,
    body: {
      error: {
        code: "management_original_region_report_snapshot_unavailable",
      },
    },
  });
});
