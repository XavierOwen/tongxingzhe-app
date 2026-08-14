import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import type {VerifiedIdentity} from "../src/identity.js";
import type {PersonalRelationshipStageChangePeriod} from "../src/personal-relationship-stage-change-summary.js";
import {createBackendServer} from "../src/server.js";

const identity = {
  issuer: "https://synthetic-stage-change-http.example.test/auth/v1",
  subject: "stage-change-http-owner",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const fromUtc = "2030-01-01T00:00:00.000Z";
const untilUtc = "2030-02-01T00:00:00.000Z";

test("stage-change route returns a no-store fixed personal result", async () => {
  let received: [VerifiedIdentity, PersonalRelationshipStageChangePeriod] | undefined;
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: neverContextStore(),
    personalRelationshipStageChangeSummaryStore: {
      read: async (...values) => {
        received = values;
        return summary();
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(url(address.port), {
    headers: {authorization: "Bearer token"},
  });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(received, [identity, {fromUtc, untilUtc}]);
  assert.deepEqual(body, {
    result: {
      contract_id: "personal_relationship_stage_change_summary_result_v1",
      project_id: projectId,
      time_basis: "relationshipChangedAtUtc",
      period: {from_utc: fromUtc, until_utc: untilUtc},
      data_cutoff_utc: "2020-02-02T00:00:00.000Z",
      authorized_at_utc: "2020-02-02T00:00:00.000Z",
      value: {
        event_count: 5,
        distinct_relationship_count: 4,
        upward_count: 3,
        downward_count: 2,
      },
    },
  });
  assert.doesNotMatch(
    JSON.stringify(body),
    /subject|workspace|display_name|phone|email|note|sql/i,
  );
});

test("stage-change route authenticates before rejecting request shape", async () => {
  let verifies = 0;
  let reads = 0;
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => {
        verifies++;
        return identity;
      },
    },
    contextStore: neverContextStore(),
    personalRelationshipStageChangeSummaryStore: {
      read: async () => {
        reads++;
        return summary();
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const base = `http://127.0.0.1:${address.port}` +
    "/v1/personal/relationship-stage-change-summary";

  const unauthenticated = await fetch(`${base}?project_id=forged`);
  assert.equal(unauthenticated.status, 401);
  assert.equal(unauthenticated.headers.get("cache-control"), "no-store");
  const duplicate = await fetch(
    `${base}?from_utc=${encodeURIComponent(fromUtc)}` +
    `&from_utc=${encodeURIComponent(fromUtc)}` +
    `&until_utc=${encodeURIComponent(untilUtc)}`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(duplicate.status, 400);
  assert.equal(duplicate.headers.get("cache-control"), "no-store");
  assert.deepEqual(await duplicate.json(), {error: {
    code: "invalid_personal_relationship_stage_change_summary_request",
  }});
  const withBody = await rawGet(
    address.port,
    "/v1/personal/relationship-stage-change-summary" +
      `?from_utc=${encodeURIComponent(fromUtc)}` +
      `&until_utc=${encodeURIComponent(untilUtc)}`,
    {authorization: "Bearer token", "content-length": "2"},
    "{}",
  );
  assert.equal(withBody.status, 400);
  assert.equal(verifies, 2);
  assert.equal(reads, 0);
});

test("stage-change route reports a missing adapter after authentication", async () => {
  const server = createBackendServer({
    identityVerifier: {verify: async () => identity},
    contextStore: neverContextStore(),
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(url(address.port), {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(response.status, 503);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {error: {
    code: "personal_relationship_stage_change_summary_unavailable",
  }});
});

function summary() {
  return {
    contractId: "personal_relationship_stage_change_summary_result_v1" as const,
    projectId,
    timeBasis: "relationshipChangedAtUtc" as const,
    period: {fromUtc, untilUtc},
    dataCutoffUtc: "2020-02-02T00:00:00.000Z",
    authorizedAtUtc: "2020-02-02T00:00:00.000Z",
    value: {
      eventCount: 5,
      distinctRelationshipCount: 4,
      upwardCount: 3,
      downwardCount: 2,
    },
  };
}

function neverContextStore() {
  return {
    loadOrCreate: async (): Promise<never> => {
      throw new Error("route must not load a separately supplied context");
    },
  };
}

function url(port: number): string {
  return `http://127.0.0.1:${port}/v1/personal/relationship-stage-change-summary` +
    `?from_utc=${encodeURIComponent(fromUtc)}` +
    `&until_utc=${encodeURIComponent(untilUtc)}`;
}

async function listen(
  server: ReturnType<typeof createBackendServer>,
): Promise<AddressInfo> {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return server.address() as AddressInfo;
}

function close(server: ReturnType<typeof createBackendServer>): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}

function rawGet(
  port: number,
  path: string,
  headers: Record<string, string>,
  body: string,
): Promise<{status: number; body: unknown}> {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      {host: "127.0.0.1", port, path, method: "GET", headers},
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        response.on("end", () => resolve({
          status: response.statusCode ?? 0,
          body: JSON.parse(Buffer.concat(chunks).toString("utf8")),
        }));
      },
    );
    request.on("error", reject);
    request.end(body);
  });
}
