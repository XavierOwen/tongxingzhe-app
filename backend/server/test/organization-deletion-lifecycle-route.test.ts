import assert from "node:assert/strict";
import {request as httpRequest, type IncomingHttpHeaders, type Server} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";
import {
  OrganizationDeletionLifecycleStoreError,
  type OrganizationDeletionLifecycleStore,
} from "../src/organization-deletion-lifecycle.js";
import {createBackendServer} from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const requestId = "123e4567-e89b-12d3-a456-426614174001";
const deletionRequestId = "123e4567-e89b-12d3-a456-426614174002";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const deletionReceipt = {
  organizationDeletionContractId: "organization-deletion-request:v1" as const,
  organizationWorkspaceId: workspaceId,
  deletionRequestId,
  effectiveAtUtc: "2030-01-01T00:00:00.123456Z",
  purgeAfterUtc: "2030-01-31T00:00:00.123456Z",
};
const restorationReceipt = {
  organizationDeletionRestoreContractId: "organization-deletion-restore:v1" as const,
  organizationWorkspaceId: workspaceId,
  deletionRequestId,
  restoredAtUtc: "2030-01-02T03:04:05.123456Z",
};

test("raw lifecycle paths fail closed before authentication; unsupported methods do not dispatch", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createServer({
    verify: async () => {
      verifierCalls += 1;
      return identity;
    },
    store: {
      listDeletionEligibleOrganizations: async () => [],
      requestDeletion: async () => {
        storeCalls += 1;
        return deletionReceipt;
      },
      restore: async () => {
        storeCalls += 1;
        return restorationReceipt;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [method, path] of [
    ["POST", `/v1/organizations/${workspaceId}/deletion-requests/`],
    ["POST", `/v1/organizations/${workspaceId}%2F/deletion-requests`],
    ["POST", `/v1/organizations/%31${workspaceId.slice(1)}/restorations`],
    ["POST", "/v1/organizations/./restorations"],
    ["DELETE", `/v1/organizations/${workspaceId}/restorations`],
  ] as const) {
    const response = await rawRequest(
      address.port,
      method,
      path,
      {authorization: "Bearer token"},
      "not-json",
    );
    assertResponse(response, 404, {error: {code: "not_found"}});
  }
  assert.equal(verifierCalls, 0);
  assert.equal(storeCalls, 0);
});

test("lifecycle route authenticates before query, path, and body checks", async () => {
  let verifierCalls = 0;
  let bodyCalls = 0;
  let storeCalls = 0;
  const server = createServer({
    verify: async (token) => {
      verifierCalls += 1;
      if (token === "invalid") throw new IdentityVerificationError("unauthenticated");
      return identity;
    },
    store: {
      listDeletionEligibleOrganizations: async () => [],
      requestDeletion: async () => {
        storeCalls += 1;
        return deletionReceipt;
      },
      restore: async () => {
        storeCalls += 1;
        return restorationReceipt;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const unauthenticatedQuery = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/deletion-requests?`,
    {authorization: "Bearer invalid"},
    "not-json",
  );
  assertResponse(unauthenticatedQuery, 401, {error: {code: "unauthenticated"}});

  for (const path of [
    `/v1/organizations/${workspaceId}/deletion-requests?`,
    "/v1/organizations/not-a-uuid/deletion-requests",
  ]) {
    const response = await rawRequest(
      address.port,
      "POST",
      path,
      {authorization: "Bearer valid"},
      "not-json",
    );
    assertResponse(response, 400, {
      error: {code: "invalid_organization_deletion_request"},
    });
  }
  assert.equal(verifierCalls, 3);
  assert.equal(bodyCalls, 0);
  assert.equal(storeCalls, 0);
});

test("HTTP exposes exact deletion and restoration receipts after store completion", async () => {
  let release: (() => void) | undefined;
  let started: (() => void) | undefined;
  const storeStarted = new Promise<void>((resolve) => { started = resolve; });
  const server = createServer({
    verify: async () => identity,
    store: {
      listDeletionEligibleOrganizations: async () => [],
      requestDeletion: async () => {
        started?.();
        await new Promise<void>((resolve) => { release = resolve; });
        return deletionReceipt;
      },
      restore: async () => restorationReceipt,
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  let settled = false;
  const pending = rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/deletion-requests`,
    {authorization: "Bearer token"},
    JSON.stringify({request_id: requestId}),
  ).then((result) => {
    settled = true;
    return result;
  });
  await storeStarted;
  assert.equal(settled, false);
  release?.();
  const deletion = await pending;
  assertResponse(deletion, 200, {
    organization_deletion_contract_id: "organization-deletion-request:v1",
    organization_workspace_id: workspaceId,
    deletion_request_id: deletionRequestId,
    effective_at_utc: deletionReceipt.effectiveAtUtc,
    purge_after_utc: deletionReceipt.purgeAfterUtc,
  });

  const restore = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/restorations`,
    {authorization: "Bearer token"},
    JSON.stringify({
      request_id: requestId,
      deletion_request_id: deletionRequestId,
    }),
  );
  assertResponse(restore, 200, {
    organization_deletion_restore_contract_id: "organization-deletion-restore:v1",
    organization_workspace_id: workspaceId,
    deletion_request_id: deletionRequestId,
    restored_at_utc: restorationReceipt.restoredAtUtc,
  });
});

test("eligibility raw path and method variants stay 404 before authentication", async () => {
  let calls = 0;
  const server = createServer({
    verify: async () => { calls += 1; return identity; },
    store: {
      listDeletionEligibleOrganizations: async () => { calls += 1; return []; },
      requestDeletion: async () => { throw new Error("mutation must not run"); },
      restore: async () => { throw new Error("mutation must not run"); },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  for (const [method, path] of [
    ["POST", "/v1/organizations/deletion-eligibility"],
    ["HEAD", "/v1/organizations/deletion-eligibility"],
    ["GET", "/v1/organizations/deletion-eligibility/"],
    ["GET", "/v1/organizations/%64eletion-eligibility"],
    ["GET", "/v1/organizations/./deletion-eligibility"],
    ["GET", "/v1//organizations/deletion-eligibility"],
    ["GET", "/v1/organizations/deletion-eligibility#fragment"],
  ]) {
    if (method === "HEAD") {
      const response = await fetch(`http://127.0.0.1:${address.port}${path}`, {method});
      assert.equal(response.status, 404);
      assert.equal(response.headers.get("cache-control"), "no-store");
    } else {
      assertResponse(await rawRequest(address.port, method!, path!,
        {authorization: "Bearer token"}, ""), 404, {error: {code: "not_found"}});
    }
  }
  assert.equal(calls, 0);
});

test("eligibility HTTP authenticates before query/body and never dispatches lifecycle writes", async () => {
  const events: string[] = [];
  const server = createServer({
    verify: async (token) => {
      events.push("identity");
      if (token === "invalid") throw new IdentityVerificationError("unauthenticated");
      return identity;
    },
    store: {
      listDeletionEligibleOrganizations: async (value) => {
        events.push("store");
        assert.deepEqual(value, identity);
        return [workspaceId];
      },
      requestDeletion: async () => { throw new Error("mutation must not run"); },
      restore: async () => { throw new Error("mutation must not run"); },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  for (const [query, body] of [["?", ""], ["?x=1", ""], ["", "not-json"]]) {
    for (const token of ["invalid", "valid"]) {
      events.length = 0;
      const response = await rawRequest(address.port, "GET",
        `/v1/organizations/deletion-eligibility${query}`,
        {authorization: `Bearer ${token}`}, body!);
      assertResponse(response, token === "invalid" ? 401 : 400, {
        error: {code: token === "invalid" ? "unauthenticated"
          : "invalid_organization_deletion_eligibility_request"},
      });
      assert.deepEqual(events, ["identity"]);
    }
  }
  events.length = 0;
  assertResponse(await rawRequest(address.port, "GET",
    "/v1/organizations/deletion-eligibility", {authorization: "Bearer valid"}, ""),
  200, {
    organization_deletion_eligibility_contract_id: "organization-deletion-eligibility:v1",
    organization_workspace_ids: [workspaceId],
  });
  assert.deepEqual(events, ["identity", "store"]);
});

test("eligibility HTTP exposes empty success and fixed store errors", async () => {
  let outcome: readonly string[] | Error = [];
  const server = createServer({
    verify: async () => identity,
    store: {
      listDeletionEligibleOrganizations: async () => {
        if (outcome instanceof Error) throw outcome;
        return outcome;
      },
      requestDeletion: async () => { throw new Error("mutation must not run"); },
      restore: async () => { throw new Error("mutation must not run"); },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  assertResponse(await rawRequest(address.port, "GET",
    "/v1/organizations/deletion-eligibility", {authorization: "Bearer token"}, ""),
  200, {
    organization_deletion_eligibility_contract_id: "organization-deletion-eligibility:v1",
    organization_workspace_ids: [],
  });
  for (const [error, status, code] of [
    [new OrganizationDeletionLifecycleStoreError("organization_deletion_eligibility_forbidden"),
      403, "organization_deletion_eligibility_forbidden"],
    [new Error("private identity / SQL / data"), 503, "organization_deletion_eligibility_unavailable"],
  ] as const) {
    outcome = error;
    assertResponse(await rawRequest(address.port, "GET",
      "/v1/organizations/deletion-eligibility", {authorization: "Bearer token"}, ""),
    status, {error: {code}});
  }
});

function createServer(options: {
  readonly verify: (token: string) => Promise<VerifiedIdentity>;
  readonly store: OrganizationDeletionLifecycleStore;
}): Server {
  return createBackendServer({
    identityVerifier: {verify: options.verify},
    organizationDeletionLifecycleStore: options.store,
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("context must not run for lifecycle routes");
      },
    },
  });
}

type RawResponse = {
  readonly status: number;
  readonly headers: IncomingHttpHeaders;
  readonly body: unknown;
};

function rawRequest(
  port: number,
  method: string,
  path: string,
  headers: Readonly<Record<string, string>>,
  body: string,
): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const request = httpRequest({
      host: "127.0.0.1",
      port,
      method,
      path,
      headers: {
        ...headers,
        "content-length": String(Buffer.byteLength(body)),
      },
    }, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("end", () => {
        try {
          resolve({
            status: response.statusCode ?? 0,
            headers: response.headers,
            body: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown,
          });
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on("error", reject);
    request.end(body);
  });
}

function assertResponse(response: RawResponse, status: number, body: unknown): void {
  assert.equal(response.status, status);
  assert.equal(response.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(response.headers["cache-control"], "no-store");
  assert.deepEqual(response.body, body);
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

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
