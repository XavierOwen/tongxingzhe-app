import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementInterestReportSnapshotStoreError,
} from "../src/management-interest-report-snapshots.js";
import {createBackendServer} from "../src/server.js";

const projectId = "6f130000-0000-4000-8000-000000000001";
const snapshotId = "6fa00000-0000-4000-8000-000000000001";
const endpointPath =
  `/v1/projects/${projectId}/management-interest-report-snapshots/${snapshotId}`;
const identity = {issuer: "issuer", subject: "subject"};
const accessEventId = "6fd00000-0000-4000-8000-000000000001";
const report = {
  report_id: "contact_sessions_by_interest_level_two_periods",
  cells: [{
    period_key: "current",
    interest_level: 0,
    cell_order: 5,
    privacy_status: "suppressed",
    value_count: null,
  }],
};

test("interest route uses its adapter, waits for it, and sets JSON no-store headers", async () => {
  let finishRead: (() => void) | undefined;
  const readGate = new Promise<void>((resolve) => {finishRead = resolve;});
  let contextCalls = 0;
  let genericStoreCalls = 0;
  let currentCityStoreCalls = 0;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {
        contextCalls += 1;
        throw new Error("SessionContext must not authorize interest reads");
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
      read: async (receivedIdentity, receivedProjectId, receivedSnapshotId) => {
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

  let responseSettled = false;
  const responsePromise = fetch(`http://127.0.0.1:${address.port}${endpointPath}`, {
    headers: {authorization: "Bearer token"},
  }).then((response) => {
    responseSettled = true;
    return response;
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(responseSettled, false);
  finishRead?.();

  const response = await responsePromise;
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    access_event_id: accessEventId,
    snapshot_id: snapshotId,
    report,
  });
  assert.equal(contextCalls, 0);
  assert.equal(genericStoreCalls, 0);
  assert.equal(currentCityStoreCalls, 0);
});

test("interest route authenticates before malformed path, query, body, or missing store", async () => {
  let verifyCalls = 0;
  let contextCalls = 0;
  let genericStoreCalls = 0;
  let currentCityStoreCalls = 0;
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
      loadOrCreate: async () => {
        contextCalls += 1;
        throw new Error("context must not run");
      },
    },
    managementReportSnapshotStore: {
      read: async () => {
        genericStoreCalls += 1;
        throw new Error("generic reader must not run");
      },
    },
    managementCurrentCityReportSnapshotStore: {
      read: async () => {
        currentCityStoreCalls += 1;
        throw new Error("current-city reader must not run");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const unauthenticated = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-interest-report-snapshots/not-a-uuid?filter=secret",
  );
  assert.equal(unauthenticated.status, 401);
  assert.equal(unauthenticated.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(unauthenticated.headers.get("cache-control"), "no-store");
  assert.deepEqual(await unauthenticated.json(), {
    error: {code: "unauthenticated"},
  });
  assert.equal(verifyCalls, 0);

  const invalidBearer = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-interest-report-snapshots/not-a-uuid?filter=secret",
    {headers: {authorization: "Bearer invalid"}},
  );
  assert.equal(invalidBearer.status, 401);
  assert.equal(invalidBearer.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(invalidBearer.headers.get("cache-control"), "no-store");
  assert.deepEqual(await invalidBearer.json(), {
    error: {code: "unauthenticated"},
  });
  assert.equal(verifyCalls, 1);

  const invalidPath = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-interest-report-snapshots/not-a-uuid",
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(invalidPath.status, 400);
  assert.equal(invalidPath.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(invalidPath.headers.get("cache-control"), "no-store");
  assert.deepEqual(await invalidPath.json(), {
    error: {code: "invalid_management_interest_report_snapshot_request"},
  });

  const query = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}?filter=secret`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(query.status, 400);
  assert.equal(query.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(query.headers.get("cache-control"), "no-store");
  assert.deepEqual(await query.json(), {
    error: {code: "invalid_management_interest_report_snapshot_request"},
  });

  const contentLengthBody = await rawRequest(
    address.port,
    endpointPath,
    {
      authorization: "Bearer token",
      "content-length": "2",
    },
    "{}",
  );
  assert.equal(contentLengthBody.status, 400);
  assert.equal(contentLengthBody.contentType, "application/json; charset=utf-8");
  assert.equal(contentLengthBody.cacheControl, "no-store");
  assert.deepEqual(contentLengthBody.json, {
    error: {code: "invalid_management_interest_report_snapshot_request"},
  });

  const transferEncodingBody = await rawRequest(
    address.port,
    endpointPath,
    {
      authorization: "Bearer token",
      "transfer-encoding": "chunked",
    },
    "{}",
  );
  assert.equal(transferEncodingBody.status, 400);
  assert.equal(transferEncodingBody.contentType, "application/json; charset=utf-8");
  assert.equal(transferEncodingBody.cacheControl, "no-store");
  assert.deepEqual(transferEncodingBody.json, {
    error: {code: "invalid_management_interest_report_snapshot_request"},
  });

  const verifierUnavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer unavailable"}},
  );
  assert.equal(verifierUnavailable.status, 503);
  assert.equal(verifierUnavailable.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(verifierUnavailable.headers.get("cache-control"), "no-store");
  assert.deepEqual(await verifierUnavailable.json(), {
    error: {code: "management_interest_report_snapshot_unavailable"},
  });

  const unavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(unavailable.status, 503);
  assert.equal(unavailable.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(unavailable.headers.get("cache-control"), "no-store");
  assert.deepEqual(await unavailable.json(), {
    error: {code: "management_interest_report_snapshot_unavailable"},
  });

  const wrongMethod = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {method: "POST", headers: {authorization: "Bearer token"}},
  );
  assert.equal(wrongMethod.status, 404);
  assert.equal(wrongMethod.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(wrongMethod.headers.get("cache-control"), "no-store");

  assert.equal(contextCalls, 0);
  assert.equal(genericStoreCalls, 0);
  assert.equal(currentCityStoreCalls, 0);
});

test("interest route maps typed and unknown store errors without leaking details", async () => {
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
    managementReportSnapshotStore: {
      read: async () => {throw new Error("generic reader must not run");},
    },
    managementCurrentCityReportSnapshotStore: {
      read: async () => {throw new Error("current-city reader must not run");},
    },
    managementInterestReportSnapshotStore: {
      read: async () => {
        if (outcome.kind === "forbidden") {
          throw new ManagementInterestReportSnapshotStoreError("forbidden");
        }
        if (outcome.kind === "unavailable") {
          throw new Error(
            "SQLSTATE 22P02 for subject management-interest-viewer",
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
        error: {code: "management_interest_report_snapshot_forbidden"},
      },
    },
    {
      outcome: {kind: "not_found"},
      status: 404,
      body: {
        error: {
          code: "management_interest_report_snapshot_not_found",
          access_event_id: accessEventId,
        },
      },
    },
    {
      outcome: {kind: "untrusted"},
      status: 409,
      body: {
        error: {
          code: "management_interest_report_snapshot_untrusted",
          access_event_id: accessEventId,
        },
      },
    },
    {
      outcome: {kind: "unavailable"},
      status: 503,
      body: {
        error: {code: "management_interest_report_snapshot_unavailable"},
      },
    },
  ];

  for (const expected of cases) {
    outcome = expected.outcome;
    const response = await fetch(
      `http://127.0.0.1:${address.port}${endpointPath}`,
      {headers: {authorization: "Bearer token"}},
    );
    assert.equal(response.status, expected.status);
    assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
    assert.equal(response.headers.get("cache-control"), "no-store");
    const text = await response.text();
    assert.deepEqual(JSON.parse(text), expected.body);
    assert.doesNotMatch(
      text,
      /22P02|SQLSTATE|management-interest-viewer|database detail|protected_report|value_count/,
    );
  }
});

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
