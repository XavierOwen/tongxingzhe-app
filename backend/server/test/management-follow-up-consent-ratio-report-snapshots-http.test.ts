import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementFollowUpConsentRatioReportSnapshotStoreError,
  readManagementFollowUpConsentRatioReportSnapshot,
  type ManagementFollowUpConsentRatioReportSnapshotRead,
} from "../src/management-follow-up-consent-ratio-report-snapshots.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "management-follow-up-consent-ratio-viewer",
};
const projectId = "7b130000-0000-4000-8000-000000000001";
const snapshotId = "7ba00000-0000-4000-8000-000000000001";
const accessEventId = "7bd00000-0000-4000-8000-000000000001";
const report = {
  report_id: "contact_target_follow_up_consent_ratio_two_periods",
  period_results: [],
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

function completed(): ManagementFollowUpConsentRatioReportSnapshotRead {
  return {
    status: "completed",
    accessEventId,
    requestedSnapshotId: snapshotId,
    resolvedSnapshotId: snapshotId,
    protectedReport: report,
  };
}

test("follow-up consent-ratio HTTP handler authenticates before validation or storage", async () => {
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
    await readManagementFollowUpConsentRatioReportSnapshot(
      request({authorization: undefined, projectId: "not-a-uuid"}),
      dependencies,
    ),
    {status: 401, body: {error: {code: "unauthenticated"}}},
  );
  assert.equal(verifyCalls, 0);

  assert.deepEqual(
    await readManagementFollowUpConsentRatioReportSnapshot(
      request({projectId: "not-a-uuid", hasQuery: true, hasBody: true}),
      dependencies,
    ),
    {
      status: 400,
      body: {
        error: {
          code: "invalid_management_follow_up_consent_ratio_report_snapshot_request",
        },
      },
    },
  );
  assert.equal(verifyCalls, 1);
  assert.equal(storeCalls, 0);
});

test("invalid bearer is rejected before malformed resources or storage", async () => {
  let storeCalls = 0;
  const result = await readManagementFollowUpConsentRatioReportSnapshot(
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

test("authenticated malformed requests do not call the consent-ratio store", async () => {
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
    const result = await readManagementFollowUpConsentRatioReportSnapshot(
      invalid,
      dependencies,
    );
    assert.deepEqual(result, {
      status: 400,
      body: {
        error: {
          code: "invalid_management_follow_up_consent_ratio_report_snapshot_request",
        },
      },
    });
  }
  assert.equal(storeCalls, 0);
});

test("follow-up consent-ratio HTTP handler waits for the adapter and emits the fixed wire", async () => {
  let finishRead: (() => void) | undefined;
  let storeCalls = 0;
  const readGate = new Promise<void>((resolve) => {finishRead = resolve;});
  const resultPromise = readManagementFollowUpConsentRatioReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async (receivedIdentity, receivedProjectId, receivedSnapshotId) => {
          storeCalls += 1;
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
  assert.equal(storeCalls, 1);
});

test("typed outcomes and unexpected errors map to stable redacted responses", async () => {
  const outcomes: ReadonlyArray<{
    readonly stored: ManagementFollowUpConsentRatioReportSnapshotRead;
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
      code: "management_follow_up_consent_ratio_report_snapshot_not_found",
    },
    {
      stored: {
        status: "untrusted_provenance",
        accessEventId,
        requestedSnapshotId: snapshotId,
        resolvedSnapshotId: snapshotId,
      },
      status: 409,
      code: "management_follow_up_consent_ratio_report_snapshot_untrusted",
    },
  ];

  for (const outcome of outcomes) {
    const result = await readManagementFollowUpConsentRatioReportSnapshot(
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
    assert.equal("report" in result.body, false);
  }

  const forbidden = await readManagementFollowUpConsentRatioReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw new ManagementFollowUpConsentRatioReportSnapshotStoreError(
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
        code: "management_follow_up_consent_ratio_report_snapshot_forbidden",
      },
    },
  });

  const unknown = await readManagementFollowUpConsentRatioReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw Object.assign(
            new Error(
              "secret SQLSTATE 22P02, subject management-follow-up-consent-ratio-viewer, " +
              "protected_report period_results yes_count",
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
        code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
      },
    },
  });
  assert.doesNotMatch(
    JSON.stringify(unknown),
    /22P02|secret|management-follow-up-consent-ratio-viewer|protected_report|period_results|yes_count/,
  );

  const parserFailure = await readManagementFollowUpConsentRatioReportSnapshot(
    request(),
    {
      identityVerifier: {verify: async () => identity},
      snapshotStore: {
        read: async () => {
          throw new Error(
            "invalid follow-up consent-ratio management report snapshot access result: protected_report",
          );
        },
      },
    },
  );
  assert.deepEqual(parserFailure, {
    status: 503,
    body: {
      error: {
        code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(parserFailure), /protected_report/);
});

test("verifier and absent-store failures remain stable and redacted", async () => {
  const invalidIdentity = await readManagementFollowUpConsentRatioReportSnapshot(
    request(),
    {
      identityVerifier: {
        verify: async () => {throw new IdentityVerificationError();},
      },
      snapshotStore: {read: async () => completed()},
    },
  );
  assert.deepEqual(invalidIdentity, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });

  const verifierUnavailable =
    await readManagementFollowUpConsentRatioReportSnapshot(
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
        code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
      },
    },
  });
  assert.doesNotMatch(JSON.stringify(verifierUnavailable), /jwks|secret/);

  const missingStore = await readManagementFollowUpConsentRatioReportSnapshot(
    request(),
    {identityVerifier: {verify: async () => identity}},
  );
  assert.deepEqual(missingStore, {
    status: 503,
    body: {
      error: {
        code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
      },
    },
  });
});
