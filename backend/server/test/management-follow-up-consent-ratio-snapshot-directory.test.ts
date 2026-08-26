import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementFollowUpConsentRatioSnapshotDirectoryStoreError,
  PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore,
  listManagementFollowUpConsentRatioSnapshotDirectory,
} from "../src/management-follow-up-consent-ratio-snapshot-directory.js";

const identity = {
  issuer: "https://directory-consent.synthetic/auth/v1",
  subject: "active-reader",
};
const projectId = "7bb30000-0000-4000-8000-000000000001";
const accessEventId = "7bdd0000-0000-4000-8000-000000000001";
const firstSnapshotId = "7ba00000-0000-4000-8000-000000000001";
const secondSnapshotId = "7ba00000-0000-4000-8000-000000000002";

const firstItem = {
  snapshot_id: firstSnapshotId,
  report_id: "contact_target_follow_up_consent_ratio_two_periods",
  report_version: 1,
  reporting_time_zone: "America/Chicago",
  data_cutoff_utc: "2026-08-10T05:00:00.000Z",
  released_at_utc: "2026-08-10T05:00:01.000Z",
};

const secondItem = {
  snapshot_id: secondSnapshotId,
  report_id: "contact_target_follow_up_consent_ratio_two_periods",
  report_version: 1,
  reporting_time_zone: "UTC",
  data_cutoff_utc: "2026-08-03T00:00:00.000Z",
  released_at_utc: "2026-08-03T00:00:01.000Z",
};

function directoryDocument(
  snapshots: readonly unknown[] = [firstItem, secondItem],
): Record<string, unknown> {
  return {
    access_contract_id:
      "authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1",
    access_event_id: accessEventId,
    project_id: projectId,
    snapshots,
  };
}

function withoutKey(
  value: Readonly<Record<string, unknown>>,
  key: string,
): Readonly<Record<string, unknown>> {
  return Object.fromEntries(
    Object.entries(value).filter(([entryKey]) => entryKey !== key),
  );
}

function storeFor(
  directoryResult: unknown,
): PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore {
  return new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(
    async () => ({rows: [{directory_result: directoryResult}]}),
  );
}

test("consent-ratio directory handler authenticates before request or store validation", async () => {
  let verifyCalls = 0;
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {
      verify: async () => {
        verifyCalls += 1;
        return identity;
      },
    },
    directoryStore: {
      list: async () => {
        storeCalls += 1;
        throw new Error("store must not run");
      },
    },
  };

  assert.deepEqual(
    await listManagementFollowUpConsentRatioSnapshotDirectory(
      {
        authorization: undefined,
        projectId: "not-a-uuid",
        hasQuery: true,
        hasBody: true,
      },
      dependencies,
    ),
    {status: 401, body: {error: {code: "unauthenticated"}}},
  );
  assert.equal(verifyCalls, 0);

  assert.deepEqual(
    await listManagementFollowUpConsentRatioSnapshotDirectory(
      {
        authorization: "Bearer token",
        projectId: "not-a-uuid",
        hasQuery: true,
        hasBody: true,
      },
      dependencies,
    ),
    {
      status: 400,
      body: {
        error: {
          code:
            "invalid_management_follow_up_consent_ratio_snapshot_directory_request",
        },
      },
    },
  );
  assert.equal(verifyCalls, 1);
  assert.equal(storeCalls, 0);
});

test("consent-ratio directory handler awaits the dedicated store and emits the fixed wire", async () => {
  let finishList: (() => void) | undefined;
  let storeCalls = 0;
  const listGate = new Promise<void>((resolve) => {finishList = resolve;});
  const resultPromise = listManagementFollowUpConsentRatioSnapshotDirectory(
    {
      authorization: "Bearer token",
      projectId,
      hasQuery: false,
      hasBody: false,
    },
    {
      identityVerifier: {verify: async () => identity},
      directoryStore: {
        list: async (receivedIdentity, receivedProjectId) => {
          storeCalls += 1;
          assert.deepEqual(receivedIdentity, identity);
          assert.equal(receivedProjectId, projectId);
          await listGate;
          return {
            accessContractId:
              "authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1",
            accessEventId,
            projectId,
            snapshots: [{
              snapshotId: firstSnapshotId,
              reportId: "contact_target_follow_up_consent_ratio_two_periods",
              reportVersion: 1,
              reportingTimeZone: "America/Chicago",
              dataCutoffUtc: "2026-08-10T05:00:00.000Z",
              releasedAtUtc: "2026-08-10T05:00:01.000Z",
            }],
          };
        },
      },
    },
  );
  let settled = false;
  void resultPromise.then(() => {settled = true;});
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(settled, false);
  assert.equal(storeCalls, 1);
  finishList?.();

  assert.deepEqual(await resultPromise, {
    status: 200,
    body: {
      access_event_id: accessEventId,
      project_id: projectId,
      snapshots: [{
        snapshot_id: firstSnapshotId,
        report_id: "contact_target_follow_up_consent_ratio_two_periods",
        report_version: 1,
        reporting_time_zone: "America/Chicago",
        data_cutoff_utc: "2026-08-10T05:00:00.000Z",
        released_at_utc: "2026-08-10T05:00:01.000Z",
      }],
    },
  });
  const wire = (await resultPromise).body;
  assert.deepEqual(Object.keys(wire).sort(), [
    "access_event_id",
    "project_id",
    "snapshots",
  ]);
  const snapshots = wire.snapshots as readonly Record<string, unknown>[];
  assert.deepEqual(Object.keys(snapshots[0] ?? {}).sort(), [
    "data_cutoff_utc",
    "released_at_utc",
    "report_id",
    "report_version",
    "reporting_time_zone",
    "snapshot_id",
  ]);
});

test("authenticated malformed consent-ratio directory requests do not call the store", async () => {
  let storeCalls = 0;
  const dependencies = {
    identityVerifier: {verify: async () => identity},
    directoryStore: {
      list: async () => {
        storeCalls += 1;
        throw new Error("store must not run");
      },
    },
  };
  const invalidRequests = [
    {projectId: "not-a-uuid", hasQuery: false, hasBody: false},
    {projectId, hasQuery: true, hasBody: false},
    {projectId, hasQuery: false, hasBody: true},
  ];

  for (const invalidRequest of invalidRequests) {
    assert.deepEqual(
      await listManagementFollowUpConsentRatioSnapshotDirectory(
        {authorization: "Bearer token", ...invalidRequest},
        dependencies,
      ),
      {
        status: 400,
        body: {
          error: {
            code:
              "invalid_management_follow_up_consent_ratio_snapshot_directory_request",
          },
        },
      },
    );
  }
  assert.equal(storeCalls, 0);
});

test("invalid bearer and identity verification failures stay before malformed input", async () => {
  let verifyCalls = 0;
  let storeCalls = 0;
  const store = {
    list: async () => {
      storeCalls += 1;
      throw new Error("store must not run");
    },
  };

  const invalidBearer = await listManagementFollowUpConsentRatioSnapshotDirectory(
    {
      authorization: "Basic secret",
      projectId: "not-a-uuid",
      hasQuery: true,
      hasBody: true,
    },
    {
      identityVerifier: {
        verify: async () => {
          verifyCalls += 1;
          return identity;
        },
      },
      directoryStore: store,
    },
  );
  assert.deepEqual(invalidBearer, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(verifyCalls, 0);

  const rejectedIdentity = await listManagementFollowUpConsentRatioSnapshotDirectory(
    {
      authorization: "Bearer invalid-token",
      projectId: "not-a-uuid",
      hasQuery: true,
      hasBody: true,
    },
    {
      identityVerifier: {
        verify: async () => {
          verifyCalls += 1;
          throw new IdentityVerificationError();
        },
      },
      directoryStore: store,
    },
  );
  assert.deepEqual(rejectedIdentity, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(verifyCalls, 1);
  assert.equal(storeCalls, 0);

  const verifierUnavailable = await listManagementFollowUpConsentRatioSnapshotDirectory(
    {
      authorization: "Bearer unavailable",
      projectId,
      hasQuery: false,
      hasBody: false,
    },
    {
      identityVerifier: {
        verify: async () => {throw new Error("jwks private detail");},
      },
      directoryStore: store,
    },
  );
  assert.deepEqual(verifierUnavailable, {
    status: 503,
    body: {
      error: {
        code:
          "management_follow_up_consent_ratio_snapshot_directory_unavailable",
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(verifierUnavailable), /jwks|private/);
  assert.equal(storeCalls, 0);
});

test("consent-ratio directory handler maps forbidden and unexpected store failures without details", async () => {
  const baseRequest = {
    authorization: "Bearer token",
    projectId,
    hasQuery: false,
    hasBody: false,
  };
  const identityVerifier = {verify: async () => identity};

  const forbidden = await listManagementFollowUpConsentRatioSnapshotDirectory(
    baseRequest,
    {
      identityVerifier,
      directoryStore: {
        list: async () => {
          throw new ManagementFollowUpConsentRatioSnapshotDirectoryStoreError(
            "forbidden",
          );
        },
      },
    },
  );
  assert.deepEqual(forbidden, {
    status: 403,
    body: {
      error: {
        code:
          "management_follow_up_consent_ratio_snapshot_directory_forbidden",
      },
    },
  });

  for (const error of [
    new Error(
      "secret SQLSTATE 22P02 protected_report period_results, subject active-reader",
    ),
    new Error(
      "invalid follow-up consent-ratio management report snapshot directory result",
    ),
  ]) {
    const unavailable =
      await listManagementFollowUpConsentRatioSnapshotDirectory(
        baseRequest,
        {identityVerifier, directoryStore: {list: async () => {throw error;}}},
      );
    assert.deepEqual(unavailable, {
      status: 503,
      body: {
        error: {
          code:
            "management_follow_up_consent_ratio_snapshot_directory_unavailable",
        },
      },
    });
    assert.doesNotMatch(
      JSON.stringify(unavailable),
      /secret|22P02|protected_report|period_results|active-reader|invalid follow-up/,
    );
  }

  const absentStore = await listManagementFollowUpConsentRatioSnapshotDirectory(
    baseRequest,
    {identityVerifier},
  );
  assert.deepEqual(absentStore, {
    status: 503,
    body: {
      error: {
        code:
          "management_follow_up_consent_ratio_snapshot_directory_unavailable",
      },
    },
  });
});

test("adapter calls one fixed exact-identity directory bridge", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{directory_result: directoryDocument()}]};
    },
  );

  const result = await store.list(identity, projectId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.list_authorized_management_follow_up_consent_snapshots_v1\(/,
  );
  assert.match(calls[0]?.text ?? "", /\$1::text/);
  assert.match(calls[0]?.text ?? "", /\$2::text/);
  assert.match(calls[0]?.text ?? "", /\$3::uuid/);
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject, projectId]);
  assert.deepEqual(result, {
    accessContractId:
      "authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1",
    accessEventId,
    projectId,
    snapshots: [
      {
        snapshotId: firstSnapshotId,
        reportId: "contact_target_follow_up_consent_ratio_two_periods",
        reportVersion: 1,
        reportingTimeZone: "America/Chicago",
        dataCutoffUtc: "2026-08-10T05:00:00.000Z",
        releasedAtUtc: "2026-08-10T05:00:01.000Z",
      },
      {
        snapshotId: secondSnapshotId,
        reportId: "contact_target_follow_up_consent_ratio_two_periods",
        reportVersion: 1,
        reportingTimeZone: "UTC",
        dataCutoffUtc: "2026-08-03T00:00:00.000Z",
        releasedAtUtc: "2026-08-03T00:00:01.000Z",
      },
    ],
  });
});

test("adapter accepts an empty bounded directory", async () => {
  const result = await storeFor(directoryDocument([])).list(identity, projectId);

  assert.deepEqual(result.snapshots, []);
});

test("adapter rejects malformed, extra, or unstable directory documents", async () => {
  const valid = directoryDocument();
  const invalidDirectories: readonly unknown[] = [
    {...valid, internal_user_id: "secret"},
    withoutKey(valid, "access_event_id"),
    {...valid, access_event_id: "not-a-uuid"},
    {...valid, access_contract_id: "other_v1"},
    {...valid, project_id: "7bb30000-0000-4000-8000-000000000002"},
    directoryDocument(Array.from({length: 21}, (_, index) => ({
      ...firstItem,
      snapshot_id: `7ba00000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    }))),
    directoryDocument([firstItem, firstItem]),
    directoryDocument([
      firstItem,
      {...secondItem, data_cutoff_utc: "2026-08-11T00:00:00.000Z"},
    ]),
    directoryDocument([{...firstItem, report_id: "contact_sessions_by_channel_two_periods"}]),
    directoryDocument([{...firstItem, report_version: 2}]),
    directoryDocument([{...firstItem, snapshot_id: "not-a-uuid"}]),
    directoryDocument([{...firstItem, reporting_time_zone: ""}]),
    directoryDocument([{...firstItem, reporting_time_zone: "America Chicago"}]),
    directoryDocument([{...firstItem, data_cutoff_utc: "not-a-time"}]),
    directoryDocument([{...firstItem, data_cutoff_utc: "2026-02-30T00:00:00.000Z"}]),
    directoryDocument([{...firstItem, released_at_utc: "2026-08-09T05:00:00.000Z"}]),
    directoryDocument([withoutKey(firstItem, "released_at_utc")]),
    directoryDocument([{...firstItem, source_key: "secret"}]),
  ];

  for (const directory of invalidDirectories) {
    await assert.rejects(
      storeFor(directory).list(identity, projectId),
      /invalid follow-up consent-ratio management report snapshot directory result/,
    );
  }
});

test("adapter requires exactly one named database result row", async () => {
  for (const rows of [
    [],
    [{directory_result: directoryDocument()}, {directory_result: directoryDocument()}],
    [{access_result: directoryDocument()}],
    [{}],
  ]) {
    const store = new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(
      async () => ({rows}),
    );
    await assert.rejects(
      store.list(identity, projectId),
      /invalid follow-up consent-ratio management report snapshot directory result/,
    );
  }
});

test("adapter maps only SQLSTATE 42501 to forbidden", async () => {
  const forbidden = new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(
    async () => {
      throw Object.assign(new Error("private grant detail"), {code: "42501"});
    },
  );
  await assert.rejects(
    forbidden.list(identity, projectId),
    (error: unknown) =>
      error instanceof ManagementFollowUpConsentRatioSnapshotDirectoryStoreError &&
      error.code === "forbidden" &&
      !error.message.includes("private grant detail"),
  );

  const unavailable = new Error("database is unavailable");
  const other = new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(
    async () => {
      throw unavailable;
    },
  );
  await assert.rejects(
    other.list(identity, projectId),
    (error: unknown) => error === unavailable,
  );
});
