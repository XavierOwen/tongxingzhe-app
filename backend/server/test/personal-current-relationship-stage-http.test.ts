import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {createBackendServer} from "../src/server.js";
import type {SessionContext} from "../src/session-context.js";

const context: SessionContext = {
  appUserId: "11111111-1111-4111-8111-111111111111",
  current: {
    workspace: {
      id: "22222222-2222-4222-8222-222222222222",
      kind: "personal",
      name: "个人空间",
    },
    project: {
      id: "33333333-3333-4333-8333-333333333333",
      name: "校园推广",
    },
    questionnaireVersion: {
      id: "44444444-4444-4444-8444-444444444444",
      versionNumber: 1,
    },
  },
  capabilities: [],
};

const snapshot = {
  contractId: "current_relationship_stage_distribution@1" as const,
  statisticalUnit: "targetProjectRelationship" as const,
  projectKey: context.current.project.id,
  snapshotAsOfUtc: "2030-01-15T12:00:00.000Z",
  sourceCutoffUtc: "2030-01-15T11:00:00.000Z",
  authorizedAtUtc: "2030-01-15T12:00:00.000Z",
  coverage: {total: 0, pending: 0},
  relationships: [],
};

test("current relationship route returns a no-store PII-free snapshot", async () => {
  let receivedContext: SessionContext | undefined;
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {loadOrCreate: async () => context},
    personalCurrentRelationshipStageStore: {
      read: async (value) => {
        receivedContext = value;
        return snapshot;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/personal/current-relationship-stage`,
    {headers: {authorization: "Bearer token"}},
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(receivedContext, context);
  const body = await response.json();
  assert.deepEqual(body, {
    snapshot: {
      contract_id: "current_relationship_stage_distribution@1",
      statistical_unit: "targetProjectRelationship",
      project_key: context.current.project.id,
      snapshot_as_of_utc: snapshot.snapshotAsOfUtc,
      source_cutoff_utc: snapshot.sourceCutoffUtc,
      authorized_at_utc: snapshot.authorizedAtUtc,
      coverage: {total: 0, pending: 0},
      relationships: [],
    },
  });
  assert.doesNotMatch(JSON.stringify(body), /display_name|phone|email|note|history/i);
});

test("current relationship route rejects query parameters and GET bodies", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {loadOrCreate: async () => context},
    personalCurrentRelationshipStageStore: {
      read: async () => snapshot,
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const base =
    `http://127.0.0.1:${address.port}/v1/personal/current-relationship-stage`;

  const queryResponse = await fetch(`${base}?as_of=2030-01-01`, {
    headers: {authorization: "Bearer token"},
  });
  assert.equal(queryResponse.status, 400);
  assert.deepEqual(await queryResponse.json(), {
    error: {code: "invalid_personal_current_relationship_stage_request"},
  });

  const bodyResponse = await rawGet(
    address.port,
    "/v1/personal/current-relationship-stage",
    {authorization: "Bearer token", "content-length": "2"},
    "{}",
  );
  assert.equal(bodyResponse.status, 400);
  assert.deepEqual(bodyResponse.body, {
    error: {code: "invalid_personal_current_relationship_stage_request"},
  });
});

test("current relationship route requires authentication before context access", async () => {
  let contextLoads = 0;
  const server = createBackendServer({
    identityVerifier: {verify: async () => ({issuer: "issuer", subject: "subject"})},
    contextStore: {
      loadOrCreate: async () => {
        contextLoads++;
        return context;
      },
    },
    personalCurrentRelationshipStageStore: {read: async () => snapshot},
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/personal/current-relationship-stage`,
  );
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), {error: {code: "unauthenticated"}});
  assert.equal(contextLoads, 0);
});

test("current relationship route reports a missing store without PII", async () => {
  const server = createBackendServer({
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {loadOrCreate: async () => context},
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/personal/current-relationship-stage`,
    {headers: {authorization: "Bearer token"}},
  );
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), {
    error: {code: "personal_current_relationship_stage_unavailable"},
  });
});

async function listen(server: ReturnType<typeof createBackendServer>): Promise<AddressInfo> {
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
