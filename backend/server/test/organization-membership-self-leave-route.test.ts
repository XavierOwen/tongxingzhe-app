import assert from "node:assert/strict";
import {
  request as httpRequest,
  type IncomingHttpHeaders,
  type Server,
} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";
import {
  OrganizationMembershipSelfLeaveStoreError,
  type OrganizationMembershipSelfLeaveResult,
  type OrganizationMembershipSelfLeaveStore,
} from "../src/organization-membership-self-leave.js";
import {createBackendServer} from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const requestId = "123e4567-e89b-12d3-a456-426614174001";
const membershipId = "123e4567-e89b-12d3-a456-426614174002";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example/auth/v1",
  subject: "subject-123",
};
const leaveResult: OrganizationMembershipSelfLeaveResult = {
  membershipSelfLeaveContractId: "organization-membership-self-leave:v1",
  organizationWorkspaceId: workspaceId,
  organizationMembershipId: membershipId,
  effectiveAtUtc: "2030-01-01T00:00:00.000Z",
};

test("raw self-leave aliases return 404 before authentication", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = testServer({
    identityVerifier: {verify: async () => { verifierCalls += 1; return identity; }},
    leaveStore: {leave: async () => { storeCalls += 1; return leaveResult; }},
  });
  const address = await listen(server);
  test.after(() => close(server));
  for (const [method, path] of [
    ["PUT", `/v1/organizations/${workspaceId}/membership-self-leave`],
    ["POST", `/v1/organizations/${workspaceId}/membership-self-leave/`],
    ["POST", `/v1/organizations/${workspaceId}//membership-self-leave`],
    ["POST", "/v1/organizations/./membership-self-leave"],
    ["POST", "/v1/organizations/../membership-self-leave"],
    ["POST", "/v1/organizations/%2e/membership-self-leave"],
    ["POST", "/v1/organizations/%41/membership-self-leave"],
    ["POST", `/v1/organizations/${workspaceId}/membership-self-leave/extra`],
  ] as const) {
    assertResponse(
      await rawRequest(address.port, method, path, {authorization: "Bearer token"}, "not-json"),
      404,
      {error: {code: "not_found"}},
    );
  }
  assert.equal(verifierCalls, 0);
  assert.equal(storeCalls, 0);
});

test("self-leave authenticates before query and path validation", async () => {
  let verifierCalls = 0;
  const server = testServer({
    identityVerifier: {
      verify: async (token) => {
        verifierCalls += 1;
        if (token === "invalid") throw new IdentityVerificationError("unauthenticated");
        return identity;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  assertResponse(
    await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave?`, {authorization: "Bearer invalid"}, "not-json"),
    401,
    {error: {code: "unauthenticated"}},
  );
  for (const path of [
    `/v1/organizations/${workspaceId}/membership-self-leave?`,
    `/v1/organizations/${workspaceId}/membership-self-leave?private=value`,
    "/v1/organizations/not-a-uuid/membership-self-leave",
  ]) {
    assertResponse(
      await rawRequest(address.port, "POST", path, {authorization: "Bearer token"}, "not-json"),
      400,
      {error: {code: "invalid_organization_membership_self_leave_request"}},
    );
  }
  assert.equal(verifierCalls, 4);
});

test("self-leave enforces actual-byte 1 MiB limit and exact body", async () => {
  let calls = 0;
  let received: Parameters<OrganizationMembershipSelfLeaveStore["leave"]> | undefined;
  const server = testServer({
    leaveStore: {leave: async (...args) => { calls += 1; received = args; return leaveResult; }},
  });
  const address = await listen(server);
  test.after(() => close(server));
  const validBody = JSON.stringify({request_id: requestId.toUpperCase()});
  const oneMiB = validBody + " ".repeat(1024 * 1024 - Buffer.byteLength(validBody));
  assertResponse(
    await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId.toUpperCase()}/membership-self-leave`, {authorization: "Bearer token", "transfer-encoding": "chunked"}, oneMiB),
    200,
    wireResult(),
  );
  assert.deepEqual(received, [identity, requestId, workspaceId]);
  assertResponse(
    await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave`, {authorization: "Bearer token", "transfer-encoding": "chunked"}, `${oneMiB} `),
    413,
    {error: {code: "payload_too_large"}},
  );
  for (const body of ["", "not-json"]) {
    assertResponse(
      await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave`, {authorization: "Bearer token"}, body),
      400,
      {error: {code: "invalid_json"}},
    );
  }
  for (const body of [
    JSON.stringify({}),
    JSON.stringify({request_id: requestId, actor: "forbidden"}),
    JSON.stringify([]),
  ]) {
    assertResponse(
      await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave`, {authorization: "Bearer token"}, body),
      400,
      {error: {code: "invalid_organization_membership_self_leave_request"}},
    );
  }
  assert.equal(calls, 1);
});

test("self-leave waits for its one store call before responding", async () => {
  let release: (() => void) | undefined;
  let started: (() => void) | undefined;
  const storeStarted = new Promise<void>((resolve) => { started = resolve; });
  const server = testServer({
    leaveStore: {
      leave: async () => {
        started?.();
        await new Promise<void>((resolve) => { release = resolve; });
        return leaveResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  let settled = false;
  const responsePromise = rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/membership-self-leave`,
    {authorization: "Bearer token"},
    JSON.stringify({request_id: requestId}),
  ).then((response) => { settled = true; return response; });
  await storeStarted;
  assert.equal(settled, false);
  release?.();
  assertResponse(await responsePromise, 200, wireResult());
});

test("self-leave keeps dependency and store errors stable", async () => {
  const missingBearerServer = testServer();
  const missingBearerAddress = await listen(missingBearerServer);
  assertResponse(
    await rawRequest(
      missingBearerAddress.port,
      "POST",
      `/v1/organizations/${workspaceId}/membership-self-leave`,
      {},
      JSON.stringify({request_id: requestId}),
    ),
    401,
    {error: {code: "unauthenticated"}},
  );
  await close(missingBearerServer);

  for (const verifierError of [
    new IdentityVerificationError("unavailable"),
    new Error("provider secret"),
  ]) {
    const server = testServer({
      identityVerifier: {verify: async () => { throw verifierError; }},
    });
    const address = await listen(server);
    assertResponse(
      await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave`, {authorization: "Bearer token"}, JSON.stringify({request_id: requestId})),
      503,
      {error: {code: "organization_membership_self_leave_unavailable"}},
    );
    await close(server);
  }

  const cases = [
    ["organization_membership_self_leave_unavailable", 503],
    ["invalid_organization_membership_self_leave_request", 400],
    ["organization_membership_self_leave_forbidden", 403],
    ["organization_membership_self_leave_conflict", 409],
  ] as const;
  for (const [code, status] of cases) {
    const server = testServer({
      leaveStore: {leave: async () => { throw new OrganizationMembershipSelfLeaveStoreError(code); }},
    });
    const address = await listen(server);
    assertResponse(
      await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave`, {authorization: "Bearer token"}, JSON.stringify({request_id: requestId})),
      status,
      {error: {code}},
    );
    await close(server);
  }

  for (const server of [
    testServer({missingVerifier: true}),
    testServer({missingStore: true}),
    testServer({leaveStore: {leave: async () => { throw new Error("database secret"); }}}),
  ]) {
    const address = await listen(server);
    assertResponse(
      await rawRequest(address.port, "POST", `/v1/organizations/${workspaceId}/membership-self-leave`, {authorization: "Bearer token"}, JSON.stringify({request_id: requestId})),
      503,
      {error: {code: "organization_membership_self_leave_unavailable"}},
    );
    await close(server);
  }
});

type TestVerifier = {verify(token: string): Promise<VerifiedIdentity>};

function testServer(options: {
  readonly identityVerifier?: TestVerifier;
  readonly leaveStore?: OrganizationMembershipSelfLeaveStore;
  readonly missingVerifier?: boolean;
  readonly missingStore?: boolean;
} = {}): Server {
  const dependencies = {
    identityVerifier: options.identityVerifier ?? {verify: async () => identity},
    contextStore: {loadOrCreate: async () => { throw new Error("context must not run"); }},
    ...(options.missingStore ? {} : {
      organizationMembershipSelfLeaveStore: options.leaveStore ?? {leave: async () => leaveResult},
    }),
  };
  return options.missingVerifier
    ? createBackendServer({...dependencies, identityVerifier: undefined as never})
    : createBackendServer(dependencies);
}

function wireResult() {
  return {
    membership_self_leave_contract_id: "organization-membership-self-leave:v1",
    organization_workspace_id: workspaceId,
    organization_membership_id: membershipId,
    effective_at_utc: leaveResult.effectiveAtUtc,
  };
}

function assertResponse(response: RawResponse, status: number, body: unknown): void {
  assert.equal(response.status, status);
  assert.equal(response.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(response.headers["cache-control"], "no-store");
  assert.deepEqual(response.body, body);
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
    const requestHeaders = {...headers};
    if (requestHeaders["transfer-encoding"] === undefined && requestHeaders["content-length"] === undefined) {
      requestHeaders["content-length"] = String(Buffer.byteLength(body));
    }
    const request = httpRequest({host: "127.0.0.1", port, method, path, headers: requestHeaders}, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("end", () => {
        try {
          resolve({
            status: response.statusCode ?? 0,
            headers: response.headers,
            body: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown,
          });
        } catch (error) { reject(error); }
      });
    });
    request.on("error", reject);
    request.end(body);
  });
}

async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => { server.off("error", reject); resolve(); });
  });
  return server.address() as AddressInfo;
}

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => error === undefined ? resolve() : reject(error));
  });
}
