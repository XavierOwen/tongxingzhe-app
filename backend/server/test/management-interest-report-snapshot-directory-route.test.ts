import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {IdentityVerificationError} from "../src/identity.js";
import {
  ManagementInterestReportSnapshotDirectoryStoreError,
} from "../src/management-interest-report-snapshot-directory.js";
import {createBackendServer} from "../src/server.js";

const projectId = "70130000-0000-4000-8000-000000000001";
const endpointPath =
  `/v1/projects/${projectId}/management-interest-report-snapshots`;
const identity = {issuer: "issuer", subject: "subject"};
const accessEventId = "70dd0000-0000-4000-8000-000000000001";
const snapshotId = "70a00000-0000-4000-8000-000000000001";

const snapshot = {
  snapshotId,
  reportId: "contact_sessions_by_interest_level_two_periods" as const,
  reportVersion: 1 as const,
  reportingTimeZone: "America/Chicago",
  dataCutoffUtc: "2026-08-10T05:00:00.000Z",
  releasedAtUtc: "2026-08-10T05:00:01.000Z",
};

test("interest directory route waits for its adapter and isolates the detail route", async () => {
  let finishList: (() => void) | undefined;
  const listGate = new Promise<void>((resolve) => {finishList = resolve;});
  let markListStarted: (() => void) | undefined;
  const listStarted = new Promise<void>((resolve) => {markListStarted = resolve;});
  let directoryCalls = 0;
  let detailCalls = 0;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("SessionContext must not authorize interest directory");
      },
    },
    managementInterestReportSnapshotDirectoryStore: {
      list: async (receivedIdentity, receivedProjectId) => {
        directoryCalls += 1;
        markListStarted?.();
        assert.deepEqual(receivedIdentity, identity);
        assert.equal(receivedProjectId, projectId);
        await listGate;
        return {
          accessContractId:
            "authorized_interest_management_report_snapshot_directory_v1",
          accessEventId,
          projectId,
          snapshots: [snapshot],
        };
      },
    },
    managementInterestReportSnapshotStore: {
      read: async () => {
        detailCalls += 1;
        throw new Error("detail adapter must not run for collection route");
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
  await listStarted;
  assert.equal(responseSettled, false);
  assert.equal(directoryCalls, 1);
  assert.equal(detailCalls, 0);
  finishList?.();

  const response = await responsePromise;
  assert.equal(response.status, 200);
  assertJsonNoStore(response.headers);
  assert.deepEqual(await response.json(), {
    access_event_id: accessEventId,
    project_id: projectId,
    snapshots: [{
      snapshot_id: snapshotId,
      report_id: "contact_sessions_by_interest_level_two_periods",
      report_version: 1,
      reporting_time_zone: "America/Chicago",
      data_cutoff_utc: "2026-08-10T05:00:00.000Z",
      released_at_utc: "2026-08-10T05:00:01.000Z",
    }],
  });
});

test("interest directory route authenticates before malformed input or missing storage", async () => {
  let verifyCalls = 0;
  let detailCalls = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async (token) => {
        verifyCalls += 1;
        if (token === "invalid") throw new IdentityVerificationError();
        if (token === "unavailable") throw new Error("secret verifier detail");
        return identity;
      },
    },
    contextStore: {
      loadOrCreate: async () => {throw new Error("context must not run");},
    },
    managementInterestReportSnapshotStore: {
      read: async () => {
        detailCalls += 1;
        throw new Error("detail must not run");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const unauthenticated = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-interest-report-snapshots?filter=secret",
  );
  assert.equal(unauthenticated.status, 401);
  assertJsonNoStore(unauthenticated.headers);
  assert.deepEqual(await unauthenticated.json(), {error: {code: "unauthenticated"}});
  assert.equal(verifyCalls, 0);

  const invalidBearer = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-interest-report-snapshots?filter=secret",
    {headers: {authorization: "Bearer invalid"}},
  );
  assert.equal(invalidBearer.status, 401);
  assertJsonNoStore(invalidBearer.headers);
  assert.deepEqual(await invalidBearer.json(), {error: {code: "unauthenticated"}});
  assert.equal(verifyCalls, 1);

  const invalidPath = await fetch(
    `http://127.0.0.1:${address.port}/v1/projects/not-a-uuid` +
      "/management-interest-report-snapshots",
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(invalidPath.status, 400);
  assertJsonNoStore(invalidPath.headers);
  assert.deepEqual(await invalidPath.json(), {
    error: {
      code: "invalid_management_interest_report_snapshot_directory_request",
    },
  });

  const query = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}?filter=secret`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(query.status, 400);
  assertJsonNoStore(query.headers);
  assert.deepEqual(await query.json(), {
    error: {
      code: "invalid_management_interest_report_snapshot_directory_request",
    },
  });

  const body = await rawRequest(
    address.port,
    endpointPath,
    {authorization: "Bearer token", "transfer-encoding": "chunked"},
    "{}",
  );
  assert.equal(body.status, 400);
  assert.equal(body.contentType, "application/json; charset=utf-8");
  assert.equal(body.cacheControl, "no-store");
  assert.deepEqual(body.json, {
    error: {
      code: "invalid_management_interest_report_snapshot_directory_request",
    },
  });

  const verifierUnavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer unavailable"}},
  );
  assert.equal(verifierUnavailable.status, 503);
  assertJsonNoStore(verifierUnavailable.headers);
  assert.deepEqual(await verifierUnavailable.json(), {
    error: {code: "management_interest_report_snapshot_directory_unavailable"},
  });

  const unavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(unavailable.status, 503);
  assertJsonNoStore(unavailable.headers);
  assert.deepEqual(await unavailable.json(), {
    error: {code: "management_interest_report_snapshot_directory_unavailable"},
  });

  const wrongMethod = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {method: "POST", headers: {authorization: "Bearer token"}},
  );
  assert.equal(wrongMethod.status, 404);
  assertJsonNoStore(wrongMethod.headers);
  assert.equal(detailCalls, 0);
});

test("interest directory route maps typed and unknown store errors without leaking details", async () => {
  type Outcome = "forbidden" | "unavailable";
  let outcome: Outcome = "forbidden";
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: {
      loadOrCreate: async () => {throw new Error("context must not run");},
    },
    managementInterestReportSnapshotDirectoryStore: {
      list: async () => {
        if (outcome === "forbidden") {
          throw new ManagementInterestReportSnapshotDirectoryStoreError(
            "forbidden",
          );
        }
        throw new Error("SQLSTATE 42501 secret management-viewer detail");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const forbidden = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(forbidden.status, 403);
  assertJsonNoStore(forbidden.headers);
  assert.deepEqual(await forbidden.json(), {
    error: {code: "management_interest_report_snapshot_directory_forbidden"},
  });

  outcome = "unavailable";
  const unavailable = await fetch(
    `http://127.0.0.1:${address.port}${endpointPath}`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(unavailable.status, 503);
  assertJsonNoStore(unavailable.headers);
  const body = await unavailable.text();
  assert.deepEqual(JSON.parse(body), {
    error: {code: "management_interest_report_snapshot_directory_unavailable"},
  });
  assert.doesNotMatch(body, /42501|SQLSTATE|management-viewer/);
});

async function listen(server: ReturnType<typeof createBackendServer>): Promise<AddressInfo> {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return server.address() as AddressInfo;
}

function assertJsonNoStore(headers: Headers): void {
  assert.equal(headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(headers.get("cache-control"), "no-store");
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
  readonly status: number;
  readonly contentType: string | string[] | undefined;
  readonly cacheControl: string | string[] | undefined;
  readonly json: unknown;
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
