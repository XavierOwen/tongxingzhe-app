import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementFollowUpConsentRatioReportSnapshotStoreError,
} from "../src/management-follow-up-consent-ratio-report-snapshots.js";
import {createBackendServer} from "../src/server.js";

const projectId = "6f130000-0000-4000-8000-000000000001";
const snapshotId = "6fa00000-0000-4000-8000-000000000001";
const endpointPath =
  `/v1/projects/${projectId}/management-follow-up-consent-ratio-report-snapshots/${snapshotId}`;
const identity = {
  issuer: "https://runtime-follow-up-consent-ratio.synthetic/auth/v1",
  subject: "view-only-member",
};
const accessEventId = "6fd00000-0000-4000-8000-000000000001";
const report = {
  contract_id: "management_follow_up_consent_ratio_candidate_v1",
  report_id: "contact_target_follow_up_consent_ratio_two_periods",
  status: "completed",
};

test("consent-ratio route waits for its dedicated store and never mixes stores", async () => {
  let finishRead: (() => void) | undefined;
  const readGate = new Promise<void>((resolve) => {finishRead = resolve;});
  let responseSettled = false;
  let contextCalls = 0;
  let genericStoreCalls = 0;
  let currentCityStoreCalls = 0;
  let interestStoreCalls = 0;
  let originalRegionStoreCalls = 0;
  let dedicatedStoreCalls = 0;

  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {
        contextCalls += 1;
        throw new Error("SessionContext must not authorize consent-ratio reads");
      },
    },
    managementReportSnapshotStore: {
      read: async () => {
        genericStoreCalls += 1;
        throw new Error("generic snapshot reader must not run");
      },
    },
    managementCurrentCityReportSnapshotStore: {
      read: async () => {
        currentCityStoreCalls += 1;
        throw new Error("current-city reader must not run");
      },
    },
    managementInterestReportSnapshotStore: {
      read: async () => {
        interestStoreCalls += 1;
        throw new Error("interest reader must not run");
      },
    },
    managementOriginalRegionReportSnapshotStore: {
      read: async () => {
        originalRegionStoreCalls += 1;
        throw new Error("original-region reader must not run");
      },
    },
    managementFollowUpConsentRatioReportSnapshotStore: {
      read: async (receivedIdentity, receivedProjectId, receivedSnapshotId) => {
        dedicatedStoreCalls += 1;
        assert.deepEqual(receivedIdentity, identity);
        assert.equal(receivedProjectId, projectId);
        assert.equal(receivedSnapshotId, snapshotId);
        await readGate;
        return {
          status: "completed" as const,
          accessEventId,
          requestedSnapshotId: snapshotId,
          resolvedSnapshotId: snapshotId,
          protectedReport: report,
        };
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const responsePromise = fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer token"}},
  ).then((response) => {
    responseSettled = true;
    return response;
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(responseSettled, false);
  finishRead?.();

  const response = await responsePromise;
  assert.equal(response.status, 200);
  assert.equal(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    access_event_id: accessEventId,
    snapshot_id: snapshotId,
    report,
  });
  assert.equal(contextCalls, 0);
  assert.equal(genericStoreCalls, 0);
  assert.equal(currentCityStoreCalls, 0);
  assert.equal(interestStoreCalls, 0);
  assert.equal(originalRegionStoreCalls, 0);
  assert.equal(dedicatedStoreCalls, 1);
});

test("consent-ratio route authenticates before path, query, body, or store validation", async () => {
  let verifyCalls = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async (token) => {
        verifyCalls += 1;
        if (token === "invalid") throw new IdentityVerificationError();
        if (token === "unavailable") {
          throw new Error("secret verifier detail");
        }
        return identity;
      },
    },
    contextStore: {
      loadOrCreate: async () => {throw new Error("context must not run");},
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const unauthenticated = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-follow-up-consent-ratio-report-snapshots/not-a-uuid?filter=secret",
  );
  assertResponseHeaders(unauthenticated);
  assert.equal(unauthenticated.status, 401);
  assert.deepEqual(await unauthenticated.json(), {
    error: {code: "unauthenticated"},
  });
  assert.equal(verifyCalls, 0);

  const invalidBearer = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-follow-up-consent-ratio-report-snapshots/not-a-uuid?filter=secret",
    {headers: {authorization: "Bearer invalid"}},
  );
  assertResponseHeaders(invalidBearer);
  assert.equal(invalidBearer.status, 401);
  assert.deepEqual(await invalidBearer.json(), {
    error: {code: "unauthenticated"},
  });
  assert.equal(verifyCalls, 1);

  const invalidPath = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-follow-up-consent-ratio-report-snapshots/not-a-uuid",
    {headers: {authorization: "Bearer token"}},
  );
  assertResponseHeaders(invalidPath);
  assert.equal(invalidPath.status, 400);
  assert.deepEqual(await invalidPath.json(), {
    error: {
      code: "invalid_management_follow_up_consent_ratio_report_snapshot_request",
    },
  });

  const query = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}?filter=secret`,
    {headers: {authorization: "Bearer token"}},
  );
  assertResponseHeaders(query);
  assert.equal(query.status, 400);
  assert.deepEqual(await query.json(), {
    error: {
      code: "invalid_management_follow_up_consent_ratio_report_snapshot_request",
    },
  });

  const contentLengthBody = await rawRequest(
    address.port,
    endpointPath,
    {authorization: "Bearer token", "content-length": "2"},
    "{}",
  );
  assert.equal(contentLengthBody.status, 400);
  assert.equal(
    contentLengthBody.contentType,
    "application/json; charset=utf-8",
  );
  assert.equal(contentLengthBody.cacheControl, "no-store");
  assert.deepEqual(contentLengthBody.json, {
    error: {
      code: "invalid_management_follow_up_consent_ratio_report_snapshot_request",
    },
  });

  const transferEncodingBody = await rawRequest(
    address.port,
    endpointPath,
    {authorization: "Bearer token", "transfer-encoding": "chunked"},
    "{}",
  );
  assert.equal(transferEncodingBody.status, 400);
  assert.equal(
    transferEncodingBody.contentType,
    "application/json; charset=utf-8",
  );
  assert.equal(transferEncodingBody.cacheControl, "no-store");
  assert.deepEqual(transferEncodingBody.json, {
    error: {
      code: "invalid_management_follow_up_consent_ratio_report_snapshot_request",
    },
  });

  const verifierUnavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer unavailable"}},
  );
  assertResponseHeaders(verifierUnavailable);
  assert.equal(verifierUnavailable.status, 503);
  const verifierUnavailableText = await verifierUnavailable.text();
  assert.deepEqual(JSON.parse(verifierUnavailableText), {
    error: {
      code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
    },
  });
  assert.doesNotMatch(verifierUnavailableText, /secret|verifier detail/);

  const unavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer token"}},
  );
  assertResponseHeaders(unavailable);
  assert.equal(unavailable.status, 503);
  assert.deepEqual(await unavailable.json(), {
    error: {
      code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
    },
  });

  const wrongMethod = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {method: "POST", headers: {authorization: "Bearer token"}},
  );
  assertResponseHeaders(wrongMethod);
  assert.equal(wrongMethod.status, 404);
  assert.deepEqual(await wrongMethod.json(), {error: {code: "not_found"}});
});

test("consent-ratio route maps typed outcomes and hides store details", async () => {
  type Outcome =
    | {readonly kind: "forbidden"}
    | {readonly kind: "not_found"}
    | {readonly kind: "untrusted"}
    | {readonly kind: "unavailable"};
  let outcome: Outcome = {kind: "forbidden"};
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {throw new Error("context must not run");},
    },
    managementFollowUpConsentRatioReportSnapshotStore: {
      read: async () => {
        if (outcome.kind === "forbidden") {
          throw new ManagementFollowUpConsentRatioReportSnapshotStoreError(
            "forbidden",
          );
        }
        if (outcome.kind === "unavailable") {
          throw new Error(
            "SQLSTATE 22P02 for subject view-only-member and protected_report value",
          );
        }
        if (outcome.kind === "not_found") {
          return {
            status: "not_found" as const,
            accessEventId,
            requestedSnapshotId: snapshotId,
            resolvedSnapshotId: null,
          };
        }
        return {
          status: "untrusted_provenance" as const,
          accessEventId,
          requestedSnapshotId: snapshotId,
          resolvedSnapshotId: snapshotId,
        };
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const cases: ReadonlyArray<{
    readonly outcome: Outcome;
    readonly status: number;
    readonly body: unknown;
  }> = [
    {
      outcome: {kind: "forbidden"},
      status: 403,
      body: {
        error: {
          code: "management_follow_up_consent_ratio_report_snapshot_forbidden",
        },
      },
    },
    {
      outcome: {kind: "not_found"},
      status: 404,
      body: {
        error: {
          code: "management_follow_up_consent_ratio_report_snapshot_not_found",
          access_event_id: accessEventId,
        },
      },
    },
    {
      outcome: {kind: "untrusted"},
      status: 409,
      body: {
        error: {
          code: "management_follow_up_consent_ratio_report_snapshot_untrusted",
          access_event_id: accessEventId,
        },
      },
    },
    {
      outcome: {kind: "unavailable"},
      status: 503,
      body: {
        error: {
          code: "management_follow_up_consent_ratio_report_snapshot_unavailable",
        },
      },
    },
  ];

  for (const expected of cases) {
    outcome = expected.outcome;
    const response = await fetch(
      `http://127.0.0.1:${address.port}${endpointPath}`,
      {headers: {authorization: "Bearer token"}},
    );
    assertResponseHeaders(response);
    assert.equal(response.status, expected.status);
    const responseText = await response.text();
    assert.deepEqual(JSON.parse(responseText), expected.body);
    assert.doesNotMatch(
      responseText,
      /22P02|SQLSTATE|view-only-member|protected_report|value/,
    );
  }
});

function assertResponseHeaders(response: Response): void {
  assert.equal(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  assert.equal(response.headers.get("cache-control"), "no-store");
}

async function listen(server: ReturnType<typeof createBackendServer>): Promise<AddressInfo> {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return server.address() as AddressInfo;
}

function close(server: ReturnType<typeof createBackendServer>): Promise<void> {
  return new Promise<void>((resolve) => server.close(() => resolve()));
}

function rawRequest(
  port: number,
  path: string,
  headers: Record<string, string>,
  body: string,
): Promise<{
  status: number;
  contentType: string | string[] | undefined;
  cacheControl: string | string[] | undefined;
  json: unknown;
}> {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      {hostname: "127.0.0.1", port, path, method: "GET", headers},
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk: Buffer) => chunks.push(chunk));
        response.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          try {
            resolve({
              status: response.statusCode ?? 0,
              contentType: response.headers["content-type"],
              cacheControl: response.headers["cache-control"],
              json: JSON.parse(text),
            });
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    request.on("error", reject);
    request.end(body);
  });
}
