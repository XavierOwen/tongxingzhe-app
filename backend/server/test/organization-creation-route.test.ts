import assert from "node:assert/strict";
import type {Server} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {
  OrganizationCreationIdentityError,
} from "../src/organization-creation-identity.js";
import {createBackendServer} from "../src/server.js";

const identity = {
  issuer: "https://synthetic.supabase.co/auth/v1",
  subject: "organization-creator",
  purpose: "organization_creation" as const,
};
const requestId = "11111111-1111-4111-8111-111111111111";
const creationResult = {
  creationContractId: "organization-creation:v1" as const,
  organizationWorkspaceId: "22222222-2222-4222-8222-222222222222",
  organizationMembershipId: "33333333-3333-4333-8333-333333333333",
  organizationOwnerAssignmentId: "44444444-4444-4444-8444-444444444444",
  createdAtUtc: "2030-01-02T03:04:05.678Z",
};

test("organization route waits for creation and returns the fixed no-store wire", async () => {
  let releaseStore: (() => void) | undefined;
  let markStoreStarted: (() => void) | undefined;
  const storeGate = new Promise<void>((resolve) => {releaseStore = resolve;});
  const storeStarted = new Promise<void>((resolve) => {
    markStoreStarted = resolve;
  });
  const events: string[] = [];
  const server = createBackendServer({
    ...unusedDependencies(),
    organizationCreationIdentityVerifier: {
      async verify(token) {
        events.push("identity");
        assert.equal(token, "access-token");
        return identity;
      },
    },
    organizationCreationStore: {
      async create(receivedIdentity, receivedRequestId, displayName) {
        events.push("store");
        assert.deepEqual(receivedIdentity, identity);
        assert.equal(receivedRequestId, requestId);
        assert.equal(displayName, "  \u00a0同行者\u202f  ");
        markStoreStarted?.();
        await storeGate;
        return creationResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  let responseSettled = false;
  const responsePromise = fetch(
    `http://127.0.0.1:${address.port}/v1/organizations`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer access-token",
        "content-type": "application/json",
        "idempotency-key": "must-not-replace-the-body-key",
      },
      body: JSON.stringify({
        request_id: requestId,
        display_name: "  \u00a0同行者\u202f  ",
      }),
    },
  ).then((response) => {
    responseSettled = true;
    return response;
  });
  await storeStarted;
  assert.equal(responseSettled, false);
  releaseStore?.();

  const response = await responsePromise;
  assert.equal(response.status, 200);
  assert.equal(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), {
    creation_contract_id: "organization-creation:v1",
    organization_workspace_id: creationResult.organizationWorkspaceId,
    organization_membership_id: creationResult.organizationMembershipId,
    organization_owner_assignment_id:
      creationResult.organizationOwnerAssignmentId,
    created_at_utc: creationResult.createdAtUtc,
  });
  assert.deepEqual(events, ["identity", "store"]);
});

test("organization route authenticates before query and ignores non-matches", async () => {
  let verifyCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...unusedDependencies(),
    organizationCreationIdentityVerifier: {
      async verify(token) {
        verifyCalls += 1;
        if (token === "forbidden") {
          throw new OrganizationCreationIdentityError("forbidden");
        }
        if (token === "unavailable") {
          throw new OrganizationCreationIdentityError("unavailable");
        }
        return identity;
      },
    },
    organizationCreationStore: {
      async create() {
        storeCalls += 1;
        return creationResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const baseUrl = `http://127.0.0.1:${address.port}`;

  await assertJson(
    fetch(`${baseUrl}/v1/organizations?private=value`, {
      method: "POST",
      body: "not-json",
    }),
    401,
    {error: {code: "unauthenticated"}},
  );
  assert.equal(verifyCalls, 0);
  assert.equal(storeCalls, 0);

  await assertJson(
    fetch(`${baseUrl}/v1/organizations?private=value`, {
      method: "POST",
      headers: {authorization: "Bearer access-token"},
      body: "not-json",
    }),
    400,
    {error: {code: "invalid_organization_creation_request"}},
  );
  assert.equal(verifyCalls, 1);
  assert.equal(storeCalls, 0);

  for (const [token, status, code] of [
    ["forbidden", 403, "organization_creation_forbidden"],
    ["unavailable", 503, "organization_creation_unavailable"],
  ] as const) {
    await assertJson(
      fetch(`${baseUrl}/v1/organizations`, {
        method: "POST",
        headers: {authorization: `Bearer ${token}`},
        body: "not-json",
      }),
      status,
      {error: {code}},
    );
  }
  assert.equal(storeCalls, 0);

  const callsBeforeNonMatches = verifyCalls;
  for (const [method, path] of [
    ["PUT", "/v1/organizations"],
    ["POST", "/v1/organizations/"],
    ["POST", "/v1/organization"],
  ] as const) {
    await assertJson(
      fetch(`${baseUrl}${path}`, {
        method,
        headers: {authorization: "Bearer access-token"},
        body: "not-json",
      }),
      404,
      {error: {code: "not_found"}},
    );
  }
  assert.equal(verifyCalls, callsBeforeNonMatches);
  assert.equal(storeCalls, 0);
});

test("organization route preserves shared JSON body error contracts", async () => {
  const server = createBackendServer({
    ...unusedDependencies(),
    organizationCreationIdentityVerifier: {verify: async () => identity},
    organizationCreationStore: {create: async () => creationResult},
  });
  const address = await listen(server);
  test.after(() => close(server));
  const url = `http://127.0.0.1:${address.port}/v1/organizations`;
  const headers = {authorization: "Bearer access-token"};

  for (const body of ["", "not-json"] as const) {
    await assertJson(
      fetch(url, {method: "POST", headers, body}),
      400,
      {error: {code: "invalid_json"}},
    );
  }
  await assertJson(
    fetch(url, {method: "POST", headers, body: "x".repeat(1024 * 1024 + 1)}),
    413,
    {error: {code: "payload_too_large"}},
  );
  await assertJson(
    fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({request_id: requestId}),
    }),
    400,
    {error: {code: "invalid_organization_creation_request"}},
  );
});

function unusedDependencies() {
  return {
    identityVerifier: {
      verify: async () => {
        throw new Error("generic verifier must not authorize organization creation");
      },
    },
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("SessionContext must not authorize organization creation");
      },
    },
  };
}

async function assertJson(
  responsePromise: Promise<Response>,
  status: number,
  body: unknown,
): Promise<void> {
  const response = await responsePromise;
  assert.equal(response.status, status);
  assert.equal(
    response.headers.get("content-type"),
    "application/json; charset=utf-8",
  );
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), body);
}

async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  return server.address() as AddressInfo;
}

async function close(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
