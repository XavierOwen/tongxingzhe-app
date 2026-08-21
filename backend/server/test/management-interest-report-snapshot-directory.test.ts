import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementInterestReportSnapshotDirectoryStoreError,
  PostgresManagementInterestReportSnapshotDirectoryStore,
  listManagementInterestReportSnapshotDirectory,
  type ManagementInterestReportSnapshotDirectoryRead,
} from "../src/management-interest-report-snapshot-directory.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};
const projectId = "70130000-0000-4000-8000-000000000001";
const accessEventId = "70dd0000-0000-4000-8000-000000000001";
const firstSnapshotId = "70a00000-0000-4000-8000-000000000001";
const secondSnapshotId = "70a00000-0000-4000-8000-000000000002";

const firstItem = {
  snapshot_id: firstSnapshotId,
  report_id: "contact_sessions_by_interest_level_two_periods",
  report_version: 1,
  reporting_time_zone: "America/Chicago",
  data_cutoff_utc: "2026-08-10T05:00:00.000Z",
  released_at_utc: "2026-08-10T05:00:01.000Z",
};

const secondItem = {
  snapshot_id: secondSnapshotId,
  report_id: "contact_sessions_by_interest_level_two_periods",
  report_version: 1,
  reporting_time_zone: "UTC",
  data_cutoff_utc: "2026-08-03T00:00:00.000Z",
  released_at_utc: "2026-08-03T00:00:01.000Z",
};

function request(overrides: Partial<{
  authorization: string | undefined;
  projectId: string;
  hasQuery: boolean;
  hasBody: boolean;
}> = {}) {
  return {
    authorization: "Bearer token",
    projectId,
    hasQuery: false,
    hasBody: false,
    ...overrides,
  };
}

function directoryDocument(
  snapshots: readonly unknown[] = [firstItem, secondItem],
): Record<string, unknown> {
  return {
    access_contract_id:
      "authorized_interest_management_report_snapshot_directory_v1",
    access_event_id: accessEventId,
    project_id: projectId,
    snapshots,
  };
}

function storedDirectory(): ManagementInterestReportSnapshotDirectoryRead {
  return {
    accessContractId:
      "authorized_interest_management_report_snapshot_directory_v1",
    accessEventId,
    projectId,
    snapshots: [{
      snapshotId: firstSnapshotId,
      reportId: "contact_sessions_by_interest_level_two_periods",
      reportVersion: 1,
      reportingTimeZone: "America/Chicago",
      dataCutoffUtc: "2026-08-10T05:00:00.000Z",
      releasedAtUtc: "2026-08-10T05:00:01.000Z",
    }],
  };
}

test("authorized interest directory returns only six bounded fields", async () => {
  const result = await listManagementInterestReportSnapshotDirectory(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      directoryStore: {list: async () => storedDirectory()},
    },
  );

  assert.deepEqual(result, {
    status: 200,
    body: {
      access_event_id: accessEventId,
      project_id: projectId,
      snapshots: [{
        snapshot_id: firstSnapshotId,
        report_id: "contact_sessions_by_interest_level_two_periods",
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

test("interest directory adapter uses one fixed 0065 bridge query", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementInterestReportSnapshotDirectoryStore(
    async (text, values) => {
      calls.push({text, values});
      return {rows: [{directory_result: directoryDocument()}]};
    },
  );

  const result = await store.list(identity, projectId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.list_authorized_management_interest_report_snapshots_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject, projectId]);
  assert.deepEqual(result, {
    accessContractId:
      "authorized_interest_management_report_snapshot_directory_v1",
    accessEventId,
    projectId,
    snapshots: [
      {
        snapshotId: firstSnapshotId,
        reportId: "contact_sessions_by_interest_level_two_periods",
        reportVersion: 1,
        reportingTimeZone: "America/Chicago",
        dataCutoffUtc: "2026-08-10T05:00:00.000Z",
        releasedAtUtc: "2026-08-10T05:00:01.000Z",
      },
      {
        snapshotId: secondSnapshotId,
        reportId: "contact_sessions_by_interest_level_two_periods",
        reportVersion: 1,
        reportingTimeZone: "UTC",
        dataCutoffUtc: "2026-08-03T00:00:00.000Z",
        releasedAtUtc: "2026-08-03T00:00:01.000Z",
      },
    ],
  });
});

test("interest directory parser rejects malformed, extra, or unstable documents", async () => {
  const valid = directoryDocument();
  const invalidDirectories: readonly unknown[] = [
    {...valid, internal_user_id: "secret"},
    directoryDocument(Array.from({length: 21}, (_, index) => ({
      ...firstItem,
      snapshot_id: `70a00000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    }))),
    directoryDocument([firstItem, firstItem]),
    directoryDocument([
      firstItem,
      {...secondItem, data_cutoff_utc: "2026-08-11T00:00:00.000Z"},
    ]),
    directoryDocument([{...firstItem, report_id: "contact_sessions_by_channel_two_periods"}]),
    directoryDocument([{...firstItem, report_version: 2}]),
    directoryDocument([{...firstItem, reporting_time_zone: ""}]),
    directoryDocument([{...firstItem, reporting_time_zone: "America Chicago"}]),
    directoryDocument([{...firstItem, data_cutoff_utc: "not-a-time"}]),
    directoryDocument([{...firstItem, data_cutoff_utc: "2026-02-30T00:00:00.000Z"}]),
    directoryDocument([{...firstItem, released_at_utc: "2026-08-09T05:00:00.000Z"}]),
    directoryDocument([{...firstItem, interest_level: 0}]),
  ];

  for (const directory of invalidDirectories) {
    const store = new PostgresManagementInterestReportSnapshotDirectoryStore(
      async () => ({rows: [{directory_result: directory}]}),
    );
    await assert.rejects(
      store.list(identity, projectId),
      /invalid interest management report snapshot directory result/,
    );
  }
});

test("interest directory authentication precedes request and store validation", async () => {
  let verificationCalls = 0;
  let storeCalls = 0;
  const dependencies = {
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
  };

  for (const authorization of [undefined, "Bearer invalid"]) {
    const result = await listManagementInterestReportSnapshotDirectory(
      request({
        authorization,
        projectId: "not-a-uuid",
        hasQuery: true,
        hasBody: true,
      }),
      dependencies,
    );
    assert.deepEqual(result, {
      status: 401,
      body: {error: {code: "unauthenticated"}},
    });
  }
  assert.equal(verificationCalls, 1);
  assert.equal(storeCalls, 0);
});

test("interest directory maps request, authorization, and database failures", async () => {
  const baseRequest = request();
  const identityVerifier = {verify: async () => identity};

  assert.deepEqual(
    await listManagementInterestReportSnapshotDirectory(
      {...baseRequest, projectId: "not-a-uuid"},
      {identityVerifier},
    ),
    {
      status: 400,
      body: {
        error: {
          code: "invalid_management_interest_report_snapshot_directory_request",
        },
      },
    },
  );
  assert.deepEqual(
    await listManagementInterestReportSnapshotDirectory(
      baseRequest,
      {identityVerifier},
    ),
    {
      status: 503,
      body: {
        error: {
          code: "management_interest_report_snapshot_directory_unavailable",
        },
      },
    },
  );
  for (const value of [
    {
      error: new ManagementInterestReportSnapshotDirectoryStoreError(
        "forbidden",
      ),
      status: 403,
      code: "management_interest_report_snapshot_directory_forbidden",
    },
    {
      error: new Error("secret database message"),
      status: 503,
      code: "management_interest_report_snapshot_directory_unavailable",
    },
  ]) {
    const result = await listManagementInterestReportSnapshotDirectory(
      baseRequest,
      {
        identityVerifier,
        directoryStore: {list: async () => {throw value.error;}},
      },
    );
    assert.deepEqual(result, {status: value.status, body: {error: {code: value.code}}});
    assert.doesNotMatch(JSON.stringify(result), /secret|database/);
  }
});
