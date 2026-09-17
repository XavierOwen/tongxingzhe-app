import assert from "node:assert/strict";
import { request as httpRequest, type IncomingHttpHeaders, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";

import { IdentityVerificationError, type IdentityVerifier } from "../src/identity.js";
import {
  OrganizationProjectMembershipAssignmentStoreError,
  PostgresOrganizationProjectMembershipAssignmentStore,
  type OrganizationProjectMembershipAssignmentResult,
  type OrganizationProjectMembershipAssignmentStore,
} from "../src/organization-project-membership-assignment.js";
import { createBackendServer } from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const projectId = "123e4567-e89b-12d3-a456-426614174001";
const requestId = "123e4567-e89b-12d3-a456-426614174002";
const targetParentId = "123e4567-e89b-12d3-a456-426614174003";
const memberId = "123e4567-e89b-12d3-a456-426614174004";
const identity = { issuer: " https://issuer.example ", subject: " exact subject " };
const validBody = { request_id: requestId, target_organization_membership_id: targetParentId };
const path = `/v1/organizations/${workspaceId}/projects/${projectId}/memberships`;
const bearer = { authorization: "Bearer valid" };
const result: OrganizationProjectMembershipAssignmentResult = {
  projectMembershipAssignmentContractId: "organization-project-membership-assignment:v1",
  organizationWorkspaceId: workspaceId,
  projectId,
  organizationMembershipId: targetParentId,
  projectMembershipId: memberId,
  activeFromUtc: "2030-01-01T00:00:00.123Z",
  inactiveFromUtc: null,
};
const wire = {
  project_membership_assignment_contract_id: result.projectMembershipAssignmentContractId,
  organization_workspace_id: workspaceId,
  project_id: projectId,
  organization_membership_id: targetParentId,
  project_membership_id: memberId,
  active_from_utc: result.activeFromUtc,
  inactive_from_utc: null,
};

test("assignment route returns exactly seven fields with explicit null or finite parent end and exact replay", async () => {
  let parentEnd: string | null = null;
  let calls = 0;
  const server = makeServer({ store: { assign: async (...args) => {
    calls += 1;
    assert.deepEqual(args, [identity, requestId, workspaceId, projectId, targetParentId]);
    return { ...result, inactiveFromUtc: parentEnd, actor: "private", replay: true };
  } } });
  const address = await listen(server);
  test.after(() => close(server));
  const uppercaseBody = JSON.stringify({
    request_id: requestId.toUpperCase(), target_organization_membership_id: targetParentId.toUpperCase(),
  });
  const uppercasePath = `/v1/organizations/${workspaceId.toUpperCase()}/projects/${projectId.toUpperCase()}/memberships`;
  for (const end of [null, "2030-01-02T00:00:00.004Z"]) {
    parentEnd = end;
    for (let replay = 0; replay < 2; replay += 1) {
      assertResponse(await rawRequest(address.port, "POST", uppercasePath, bearer, uppercaseBody),
      200, { ...wire, inactive_from_utc: end });
    }
  }
  assert.equal(calls, 4);
});

test("raw aliases on both selectors and wrong methods are 404 before authentication", async () => {
  let calls = 0;
  const server = makeServer({
    verifier: { verify: async () => { calls += 1; return identity; } },
    store: { assign: async () => { calls += 1; return result; } },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const aliases = [
    `${path}/`, `${path}/extra`, path.replace("/projects/", "//projects/"),
    path.replace("/memberships", "//memberships"), path.replace("/v1/", "/v1//"),
    `/v1/organizations/${workspaceId}/projects//memberships`,
    ...[".", "..", "%2e", "%2E%2E", "%41", "%2F", "%31"].flatMap((alias) =>
      [path.replace(workspaceId, alias), path.replace(projectId, alias)]),
  ];
  for (const alias of aliases) {
    assertResponse(await rawRequest(address.port, "POST", alias, bearer, "not-json"),
      404, { error: { code: "not_found" } });
  }
  for (const method of ["GET", "PUT", "PATCH", "DELETE"]) {
    assertResponse(await rawRequest(address.port, method, path, bearer, "not-json"),
      404, { error: { code: "not_found" } });
  }
  assert.equal(calls, 0);
});

test("route authenticates before query and both path UUIDs, then checks missing store before body", async () => {
  const server = makeServer({ missingStore: true });
  const address = await listen(server);
  test.after(() => close(server));
  for (const headers of [{}, { authorization: "Bearer invalid" }]) {
    assertResponse(await rawRequest(address.port, "POST", `${path}?`, headers, "not-json"),
      401, { error: { code: "unauthenticated" } });
    for (const selector of [workspaceId, projectId]) {
      assertResponse(await rawRequest(address.port, "POST", path.replace(selector, "bad-uuid"), headers, "not-json"),
        401, { error: { code: "unauthenticated" } });
    }
  }
  for (const query of ["?", "?actor=private"]) {
    assertResponse(await rawRequest(address.port, "POST", `${path}${query}`, bearer, "not-json"),
      400, { error: { code: "invalid_organization_project_membership_assignment_request" } });
  }
  for (const selector of [workspaceId, projectId]) {
    assertResponse(await rawRequest(address.port, "POST", path.replace(selector, "bad-uuid"), bearer, "not-json"),
      400, { error: { code: "invalid_organization_project_membership_assignment_request" } });
  }
  assertResponse(await rawRequest(address.port, "POST", path, bearer, "not-json"),
    503, { error: { code: "organization_project_membership_assignment_unavailable" } });
  const noVerifier = makeServer({ missingVerifier: true });
  const noVerifierAddress = await listen(noVerifier);
  test.after(() => close(noVerifier));
  assertResponse(await rawRequest(noVerifierAddress.port, "POST", `${path}?`, bearer, "not-json"),
    503, { error: { code: "organization_project_membership_assignment_unavailable" } });
  assertResponse(await rawRequest(noVerifierAddress.port, "POST", path, {}, "not-json"),
    401, { error: { code: "unauthenticated" } });
});

test("strict body rejects actor, role, capability, time and foreign scope before store", async () => {
  let calls = 0;
  const server = makeServer({ store: { assign: async () => { calls += 1; return result; } } });
  const address = await listen(server);
  test.after(() => close(server));
  const bodies = [null, [], "text", {}, { request_id: requestId },
    { target_organization_membership_id: targetParentId },
    { ...validBody, request_id: "not-uuid" }, { ...validBody, target_organization_membership_id: null },
    ...["actor", "app_user_id", "issuer", "subject", "role", "capability", "active_from_utc", "inactive_from_utc",
      "workspace_id", "organization_workspace_id", "project_id"].map((key) => ({ ...validBody, [key]: "untrusted" })),
  ];
  for (const body of bodies) {
    assertResponse(await rawRequest(address.port, "POST", path, bearer, JSON.stringify(body)),
      400, { error: { code: "invalid_organization_project_membership_assignment_request" } });
  }
  assert.equal(calls, 0);
});

test("shared reader keeps missing/text/plain Content-Type, invalid JSON and inclusive chunked 1 MiB semantics", async () => {
  let calls = 0;
  const server = makeServer({ store: { assign: async () => { calls += 1; return result; } } });
  const address = await listen(server);
  test.after(() => close(server));
  for (const contentType of [undefined, "text/plain"]) {
    assertResponse(await rawRequest(address.port, "POST", path,
      { ...bearer, ...(contentType === undefined ? {} : { "content-type": contentType }) }, JSON.stringify(validBody)),
    200, wire);
  }
  for (const body of ["", "not-json"]) {
    assertResponse(await rawRequest(address.port, "POST", path, bearer, body),
      400, { error: { code: "invalid_json" } });
  }
  const body = JSON.stringify(validBody);
  const oneMiB = body + " ".repeat(1024 * 1024 - Buffer.byteLength(body));
  assert.equal(Buffer.byteLength(oneMiB), 1024 * 1024);
  assertResponse(await rawRequest(address.port, "POST", path,
    { ...bearer, "transfer-encoding": "chunked" }, oneMiB), 200, wire);
  assertResponse(await rawRequest(address.port, "POST", path,
    { ...bearer, "transfer-encoding": "chunked" }, `${oneMiB} `),
  413, { error: { code: "payload_too_large" } });
  assert.equal(calls, 3);
});

test("typed store errors and unknown verifier/store failures expose only stable codes", async () => {
  let failure: unknown;
  const server = makeServer({ store: { assign: async () => { throw failure; } } });
  const address = await listen(server);
  test.after(() => close(server));
  for (const [code, status] of [
    ["invalid_organization_project_membership_assignment_request", 400],
    ["organization_project_membership_assignment_forbidden", 403],
    ["organization_project_membership_assignment_conflict", 409],
    ["organization_project_membership_assignment_unavailable", 503],
  ] as const) {
    failure = new OrganizationProjectMembershipAssignmentStoreError(code);
    assertResponse(await rawRequest(address.port, "POST", path, bearer, JSON.stringify(validBody)),
      status, { error: { code } });
  }
  failure = new Error("SQL constraint secret");
  assertResponse(await rawRequest(address.port, "POST", path, bearer, JSON.stringify(validBody)),
    503, { error: { code: "organization_project_membership_assignment_unavailable" } });
  for (const error of [new IdentityVerificationError("unavailable"), new Error("provider secret")]) {
    const verifierServer = makeServer({ verifier: { verify: async () => { throw error; } } });
    const verifierAddress = await listen(verifierServer);
    test.after(() => close(verifierServer));
    assertResponse(await rawRequest(verifierAddress.port, "POST", path, bearer, "not-json"),
      503, { error: { code: "organization_project_membership_assignment_unavailable" } });
  }
});

test("response waits for the single adapter query acknowledgement", async () => {
  let releaseQuery: (() => void) | undefined;
  let markStarted: (() => void) | undefined;
  const started = new Promise<void>((resolve) => { markStarted = resolve; });
  let queryCalls = 0;
  const store = new PostgresOrganizationProjectMembershipAssignmentStore(async (text, values) => {
    queryCalls += 1;
    assert.match(text, /app_data\.assign_organization_project_member_for_identity_v1/);
    assert.deepEqual(values, [identity.issuer, identity.subject, requestId, workspaceId, projectId, targetParentId]);
    markStarted?.();
    await new Promise<void>((resolve) => { releaseQuery = resolve; });
    return { rows: [wire] };
  });
  const server = makeServer({ store });
  const address = await listen(server);
  test.after(() => close(server));
  let settled = false;
  const pending = rawRequest(address.port, "POST", path, bearer, JSON.stringify(validBody)).then((response) => {
    settled = true; return response;
  });
  await started;
  assert.equal(settled, false);
  releaseQuery?.();
  assertResponse(await pending, 200, wire);
  assert.equal(queryCalls, 1);
});

function makeServer(options: {
  readonly verifier?: IdentityVerifier;
  readonly store?: OrganizationProjectMembershipAssignmentStore;
  readonly missingVerifier?: boolean;
  readonly missingStore?: boolean;
} = {}): Server {
  return createBackendServer({
    identityVerifier: options.missingVerifier ? undefined as never : options.verifier ?? {
      verify: async (token) => {
        if (token !== "valid") throw new IdentityVerificationError("unauthenticated");
        return identity;
      },
    },
    contextStore: { loadOrCreate: async () => { throw new Error("context must not run"); } },
    ...(options.missingStore ? {} : {
      organizationProjectMembershipAssignmentStore: options.store ?? { assign: async () => result },
    }),
  });
}

interface RawResponse {
  readonly status: number;
  readonly headers: IncomingHttpHeaders;
  readonly body: unknown;
}

function assertResponse(response: RawResponse, status: number, body: unknown): void {
  assert.equal(response.status, status);
  assert.equal(response.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(response.headers["cache-control"], "no-store");
  assert.deepEqual(response.body, body);
}

function rawRequest(port: number, method: string, target: string,
  headers: Readonly<Record<string, string>>, body: string): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const requestHeaders = { ...headers };
    if (requestHeaders["transfer-encoding"] === undefined && requestHeaders["content-length"] === undefined) {
      requestHeaders["content-length"] = String(Buffer.byteLength(body));
    }
    const request = httpRequest({ host: "127.0.0.1", port, method, path: target, headers: requestHeaders }, (response) => {
      const chunks: Buffer[] = [];
      response.on("data", (chunk: Buffer) => chunks.push(chunk));
      response.on("end", () => {
        try {
          resolve({ status: response.statusCode ?? 0, headers: response.headers,
            body: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown });
        } catch (error) { reject(error); }
      });
    });
    request.on("error", reject);
    if (requestHeaders["transfer-encoding"] === "chunked") {
      const bytes = Buffer.from(body);
      request.write(bytes.subarray(0, Math.floor(bytes.length / 2)));
      request.end(bytes.subarray(Math.floor(bytes.length / 2)));
    } else request.end(body);
  });
}

async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject); server.listen(0, "127.0.0.1", () => { server.off("error", reject); resolve(); });
  });
  return server.address() as AddressInfo;
}

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => { server.close((error) => { if (error === undefined) resolve(); else reject(error); }); });
}
