import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementCurrentCityReportSnapshotDirectoryStoreError,
  PostgresManagementCurrentCityReportSnapshotDirectoryStore,
  listManagementCurrentCityReportSnapshotDirectory,
  type ManagementCurrentCityReportSnapshotDirectoryRead,
} from "../src/management-current-city-report-snapshot-directory.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-viewer",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const accessEventId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const firstSnapshotId = "88888888-8888-4888-8888-888888888888";
const secondSnapshotId = "77777777-7777-4777-8777-777777777777";

const firstItem = {
  snapshot_id: firstSnapshotId,
  report_id: "contact_sessions_by_current_city_two_periods",
  report_version: 1,
  reporting_time_zone: "America/Chicago",
  data_cutoff_utc: "2026-08-10T05:00:00.000Z",
  released_at_utc: "2026-08-10T05:00:01.000Z",
};

const secondItem = {
  snapshot_id: secondSnapshotId,
  report_id: "contact_sessions_by_current_city_two_periods",
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
      "authorized_current_city_management_report_snapshot_directory_v1",
    access_event_id: accessEventId,
    project_id: projectId,
    snapshots,
  };
}

function storedDirectory(): ManagementCurrentCityReportSnapshotDirectoryRead {
  return {
    accessEventId,
    projectId,
    snapshots: [
      {
        snapshotId: firstSnapshotId,
        reportId: "contact_sessions_by_current_city_two_periods",
        reportVersion: 1,
        reportingTimeZone: "America/Chicago",
        dataCutoffUtc: "2026-08-10T05:00:00.000Z",
        releasedAtUtc: "2026-08-10T05:00:01.000Z",
      },
    ],
  };
}

test("authorized current-city directory returns only six bounded fields", async () => {
  const result = await listManagementCurrentCityReportSnapshotDirectory(
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
        report_id: "contact_sessions_by_current_city_two_periods",
        report_version: 1,
        reporting_time_zone: "America/Chicago",
        data_cutoff_utc: "2026-08-10T05:00:00.000Z",
        released_at_utc: "2026-08-10T05:00:01.000Z",
      }],
    },
  });
  assert.doesNotMatch(
    JSON.stringify(result),
    /protected_report|cells|contributor|membership|capability|subject|city_name/,
  );
});

test("current-city directory adapter uses one fixed bridge query", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresManagementCurrentCityReportSnapshotDirectoryStore(
    async (text, values) => {
      calls.push({text, values});
      return {
        rows: [{directory_result: directoryDocument()}],
      };
    },
  );

  const result = await store.list(identity, projectId);

  assert.equal(calls.length, 1);
  assert.match(
    calls[0]?.text ?? "",
    /app_data\.list_authorized_management_current_city_report_snapshots_v1/,
  );
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject, projectId]);
  assert.deepEqual(result, {
    accessEventId,
    projectId,
    snapshots: [
      {
        snapshotId: firstSnapshotId,
        reportId: "contact_sessions_by_current_city_two_periods",
        reportVersion: 1,
        reportingTimeZone: "America/Chicago",
        dataCutoffUtc: "2026-08-10T05:00:00.000Z",
        releasedAtUtc: "2026-08-10T05:00:01.000Z",
      },
      {
        snapshotId: secondSnapshotId,
        reportId: "contact_sessions_by_current_city_two_periods",
        reportVersion: 1,
        reportingTimeZone: "UTC",
        dataCutoffUtc: "2026-08-03T00:00:00.000Z",
        releasedAtUtc: "2026-08-03T00:00:01.000Z",
      },
    ],
  });
});

test("current-city directory parser rejects malformed, extra, or unstable documents", async () => {
  const valid = directoryDocument();
  const invalidDirectories: readonly unknown[] = [
    {...valid, internal_user_id: "secret"},
    directoryDocument(Array.from({length: 21}, (_, index) => ({
      ...firstItem,
      snapshot_id: `88888888-8888-4888-8888-${String(index).padStart(12, "0")}`,
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
    directoryDocument([{...firstItem, city_name: "Chicago"}]),
  ];

  for (const directory of invalidDirectories) {
    const store = new PostgresManagementCurrentCityReportSnapshotDirectoryStore(
      async () => ({rows: [{directory_result: directory}]}),
    );
    await assert.rejects(
      store.list(identity, projectId),
      /invalid current-city management report snapshot directory result/,
    );
  }
});

test("current-city directory authentication precedes request and store validation", async () => {
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
    const result = await listManagementCurrentCityReportSnapshotDirectory(
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

test("current-city directory maps request, authorization, and database failures", async () => {
  const baseRequest = request();
  const identityVerifier = {verify: async () => identity};

  assert.deepEqual(
    await listManagementCurrentCityReportSnapshotDirectory(
      {...baseRequest, projectId: "not-a-uuid"},
      {identityVerifier},
    ),
    {
      status: 400,
      body: {
        error: {
          code: "invalid_management_current_city_report_snapshot_directory_request",
        },
      },
    },
  );
  assert.deepEqual(
    await listManagementCurrentCityReportSnapshotDirectory(
      baseRequest,
      {identityVerifier},
    ),
    {
      status: 503,
      body: {
        error: {
          code: "management_current_city_report_snapshot_directory_unavailable",
        },
      },
    },
  );
  for (const value of [
    {
      error: new ManagementCurrentCityReportSnapshotDirectoryStoreError(
        "forbidden",
      ),
      status: 403,
      code: "management_current_city_report_snapshot_directory_forbidden",
    },
    {
      error: new Error("secret database message"),
      status: 503,
      code: "management_current_city_report_snapshot_directory_unavailable",
    },
  ]) {
    const result = await listManagementCurrentCityReportSnapshotDirectory(
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
