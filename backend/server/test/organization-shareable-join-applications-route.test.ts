import assert from "node:assert/strict";
import {request as httpRequest, type IncomingHttpHeaders, type Server} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import type {VerifiedIdentity} from "../src/identity.js";
import {
  OrganizationShareableJoinApplicationStoreError,
  type OrganizationShareableJoinApplicationStore,
} from "../src/organization-shareable-join-applications.js";
import {createBackendServer} from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const linkId = "123e4567-e89b-12d3-a456-426614174001";
const applicationId = "123e4567-e89b-12d3-a456-426614174002";
const membershipId = "123e4567-e89b-12d3-a456-426614174003";
const identity: VerifiedIdentity = {issuer: "https://issuer.example", subject: "subject"};
const submitResult = {
  organizationShareableJoinApplicationContractId:
    "organization-shareable-join-application:v1" as const,
  applicationId, linkId, organizationWorkspaceId: workspaceId,
  submittedAtUtc: "2030-01-01T00:00:00.000Z",
  expiresAtUtc: "2030-01-08T00:00:00.000Z",
};
const approveResult = {
  organizationShareableJoinApplicationContractId:
    "organization-shareable-join-application:v1" as const,
  applicationId, organizationWorkspaceId: workspaceId,
  organizationMembershipId: membershipId,
  approvedAtUtc: "2030-01-02T00:00:00.000Z",
};
const directoryResult = {
  organizationShareableJoinApplicationDirectoryContractId:
    "organization-shareable-join-application-directory:v1" as const,
  organizationWorkspaceId: workspaceId,
  observedAtUtc: "2030-01-02T00:00:00.000Z",
  applications: [{applicationId, linkId, submittedAtUtc: submitResult.submittedAtUtc,
    expiresAtUtc: submitResult.expiresAtUtc}],
};

test("application routes return exact receipts and bound store arguments", async () => {
  let submitArgs: unknown;
  let approveArgs: unknown;
  const server = makeServer({
    submit: async (...args) => { submitArgs = args; return submitResult; },
    approve: async (...args) => { approveArgs = args; return approveResult; },
  });
  const address = await listen(server);
  test.after(() => close(server));

  assertResponse(await request(address.port, "POST", submitPath(linkId.toUpperCase()),
    {authorization: "Bearer token"}, JSON.stringify({application_id: applicationId.toUpperCase()})),
  200, {
    organization_shareable_join_application_contract_id:
      "organization-shareable-join-application:v1",
    application_id: applicationId, link_id: linkId,
    organization_workspace_id: workspaceId,
    submitted_at_utc: submitResult.submittedAtUtc,
    expires_at_utc: submitResult.expiresAtUtc,
  });
  assert.deepEqual(submitArgs, [identity, applicationId, linkId]);

  assertResponse(await request(address.port, "POST",
    approvePath(workspaceId.toUpperCase(), applicationId.toUpperCase()),
    {authorization: "Bearer token"}, "{}"), 200, {
      organization_shareable_join_application_contract_id:
        "organization-shareable-join-application:v1",
      application_id: applicationId, organization_workspace_id: workspaceId,
      organization_membership_id: membershipId,
      approved_at_utc: approveResult.approvedAtUtc,
    });
  assert.deepEqual(approveArgs, [identity, applicationId, workspaceId]);
});

test("raw aliases and wrong methods are 404 before auth", async () => {
  let calls = 0;
  const server = createBackendServer({
    ...baseDependencies({verify: async () => { calls += 1; return identity; }}),
    organizationShareableJoinApplicationStore: okStore(),
  });
  const address = await listen(server);
  test.after(() => close(server));
  for (const [method, path] of [
    ["GET", submitPath()], ["PUT", submitPath()],
    ["POST", `${submitPath()}/`],
    ["POST", `/v1/organization-shareable-join-links/%31${linkId.slice(1)}/applications`],
    ["GET", approvePath()], ["PATCH", approvePath()],
    ["POST", `${approvePath()}/`],
    ["POST", `/v1/organizations/${workspaceId}/shareable-join-applications/%2e/approve`],
  ] as const) {
    assertResponse(await request(address.port, method, path,
      {authorization: "Bearer token"}, "not-json"), 404,
    {error: {code: "not_found"}});
  }
  assert.equal(calls, 0);
});

test("routes enforce auth-first validation, exact bodies, and stable errors", async () => {
  let storeCalls = 0;
  const store: OrganizationShareableJoinApplicationStore = {
    listPending: async () => directoryResult,
    submit: async (_identity, selectedApplicationId) => {
      storeCalls += 1;
      if (selectedApplicationId === applicationId) return submitResult;
      throw new OrganizationShareableJoinApplicationStoreError(
        "organization_shareable_join_forbidden",
      );
    },
    approve: async () => approveResult,
  };
  const server = makeServer(store);
  const address = await listen(server);
  test.after(() => close(server));
  assertResponse(await request(address.port, "POST", `${submitPath()}?x=1`, {}, "not-json"),
    401, {error: {code: "unauthenticated"}});
  assertResponse(await request(address.port, "POST", `${submitPath()}?x=1`,
    {authorization: "Bearer token"}, "not-json"), 400,
  {error: {code: "invalid_organization_shareable_join_request"}});
  assertResponse(await request(address.port, "POST", submitPath(),
    {authorization: "Bearer token"}, JSON.stringify({application_id: applicationId, extra: 1})),
  400, {error: {code: "invalid_organization_shareable_join_request"}});
  assertResponse(await request(address.port, "POST", approvePath(),
    {authorization: "Bearer token"}, JSON.stringify({extra: 1})), 400,
  {error: {code: "invalid_organization_shareable_join_request"}});
  assertResponse(await request(address.port, "POST", submitPath(),
    {authorization: "Bearer token"}, JSON.stringify({application_id: membershipId})),
  403, {error: {code: "organization_shareable_join_forbidden"}});
  assert.equal(storeCalls, 1);
});

test("routes preserve shared malformed JSON and 1 MiB body limits", async () => {
  let storeCalls = 0;
  const server = makeServer({
    submit: async () => { storeCalls += 1; return submitResult; },
    approve: async () => { storeCalls += 1; return approveResult; },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const body of ["", "not-json"]) {
    assertResponse(await request(address.port, "POST", submitPath(),
      {authorization: "Bearer token"}, body), 400,
    {error: {code: "invalid_json"}});
  }
  const limit = 1024 * 1024;
  const boundaryBody = JSON.stringify({
    padding: "a".repeat(limit - Buffer.byteLength('{"padding":""}')),
  });
  assert.equal(Buffer.byteLength(boundaryBody), limit);
  assertResponse(await request(address.port, "POST", submitPath(),
    {authorization: "Bearer token"}, boundaryBody), 400,
  {error: {code: "invalid_organization_shareable_join_request"}});
  assertResponse(await request(address.port, "POST", approvePath(),
    {authorization: "Bearer token"}, `${boundaryBody} `), 413,
  {error: {code: "payload_too_large"}});
  assert.equal(storeCalls, 0);
});

test("both routes wait for the store promise", async () => {
  for (const operation of ["submit", "approve"] as const) {
    let release: (() => void) | undefined;
    let started: (() => void) | undefined;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const began = new Promise<void>((resolve) => { started = resolve; });
    const server = makeServer({
      submit: async () => { if (operation === "submit") { started?.(); await gate; } return submitResult; },
      approve: async () => { if (operation === "approve") { started?.(); await gate; } return approveResult; },
    });
    const address = await listen(server);
    let settled = false;
    const pending = request(address.port, "POST",
      operation === "submit" ? submitPath() : approvePath(),
      {authorization: "Bearer token"},
      operation === "submit" ? JSON.stringify({application_id: applicationId}) : "{}",
    ).then((value) => { settled = true; return value; });
    await began;
    assert.equal(settled, false);
    release?.();
    assert.equal((await pending).status, 200);
    await close(server);
  }
});

function submitPath(value = linkId): string {
  return `/v1/organization-shareable-join-links/${value}/applications`;
}
function approvePath(workspace = workspaceId, application = applicationId): string {
  return `/v1/organizations/${workspace}/shareable-join-applications/${application}/approve`;
}
function okStore(): OrganizationShareableJoinApplicationStore {
  return {listPending: async () => directoryResult,
    submit: async () => submitResult, approve: async () => approveResult};
}
function makeServer(store: Omit<OrganizationShareableJoinApplicationStore, "listPending"> &
  Partial<Pick<OrganizationShareableJoinApplicationStore, "listPending">>): Server {
  return createBackendServer({
    ...baseDependencies({verify: async () => identity}),
    organizationShareableJoinApplicationStore: {...okStore(), ...store},
  });
}
function baseDependencies(identityVerifier: {verify(token: string): Promise<VerifiedIdentity>}) {
  return {
    identityVerifier,
    contextStore: {loadOrCreate: async () => { throw new Error("context must not run"); }},
  };
}
type Response = {status: number; headers: IncomingHttpHeaders; body: unknown};
function assertResponse(response: Response, status: number, body: unknown): void {
  assert.equal(response.status, status);
  assert.equal(response.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(response.headers["cache-control"], "no-store");
  assert.deepEqual(response.body, body);
}
function request(port: number, method: string, path: string,
  headers: Readonly<Record<string, string>>, body: string): Promise<Response> {
  return new Promise((resolve, reject) => {
    const req = httpRequest({host: "127.0.0.1", port, method, path,
      headers: {...(headers["transfer-encoding"] === undefined && headers["content-length"] === undefined
        ? {"content-length": String(Buffer.byteLength(body))} : {}), ...headers}}, (res) => {
      const chunks: Buffer[] = [];
      res.on("data", (chunk: Buffer) => chunks.push(chunk));
      res.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        resolve({status: res.statusCode ?? 0, headers: res.headers,
          body: text.length === 0 ? undefined : JSON.parse(text) as unknown});
      });
    });
    req.on("error", reject); req.end(body);
  });
}
async function listen(server: Server): Promise<AddressInfo> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {server.off("error", reject); resolve();});
  });
  return server.address() as AddressInfo;
}
async function close(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => server.close((error) =>
    error === undefined ? resolve() : reject(error)));
}

function directoryPath(workspace = workspaceId): string {
  return `/v1/organizations/${workspace}/shareable-join-applications`;
}

test("pending directory GET returns exact safe metadata with canonical selector and no-store", async () => {
  let args: unknown;
  const server = makeServer({...okStore(), listPending: async (...values) => {
    args = values; return directoryResult;
  }});
  const address = await listen(server);
  test.after(() => close(server));
  assertResponse(await request(address.port, "GET", directoryPath(workspaceId.toUpperCase()),
    {authorization: "Bearer token"}, ""), 200, {
    organization_shareable_join_application_directory_contract_id:
      "organization-shareable-join-application-directory:v1",
    organization_workspace_id: workspaceId, observed_at_utc: directoryResult.observedAtUtc,
    applications: [{application_id: applicationId, link_id: linkId,
      submitted_at_utc: submitResult.submittedAtUtc, expires_at_utc: submitResult.expiresAtUtc}],
  });
  assert.deepEqual(args, [identity, workspaceId]);
});

test("directory raw method and path aliases are 404 without identity or store", async () => {
  let calls = 0;
  const server = createBackendServer({...baseDependencies({verify: async () => {calls++; return identity;}}),
    organizationShareableJoinApplicationStore: {...okStore(), listPending: async () => {calls++; return directoryResult;}}});
  const address = await listen(server);
  test.after(() => close(server));
  for (const [method, path] of [
    ["POST", directoryPath()], ["PUT", directoryPath()], ["HEAD", directoryPath()],
    ["GET", directoryPath() + "/"], ["GET", directoryPath().replace(workspaceId, "%31" + workspaceId.slice(1))],
    ["GET", directoryPath(".")], ["GET", directoryPath("..")],
    ["GET", directoryPath().replace("/organizations/", "/organizations//")],
  ]) {
    const response = await request(address.port, method!, path!, {authorization: "Bearer token"}, "not-json");
    if (method === "HEAD") {
      assert.equal(response.status, 404);
      assert.equal(response.body, undefined);
      assert.equal(response.headers["cache-control"], "no-store");
    } else {
      assertResponse(response, 404, {error: {code: "not_found"}});
    }
  }
  assert.equal(calls, 0);
});

test("directory authenticates before query, body declarations, UUID, and missing store", async () => {
  let calls = 0;
  const server = createBackendServer(baseDependencies({verify: async () => {calls++; return identity;}}));
  const address = await listen(server);
  test.after(() => close(server));
  for (const [path, headers, body] of [
    [directoryPath() + "?", {}, "not-json"],
    [directoryPath("bad"), {}, "not-json"],
  ] as const) {
    assertResponse(await request(address.port, "GET", path, headers, body), 401,
      {error: {code: "unauthenticated"}});
  }
  for (const [path, headers, body] of [
    [directoryPath() + "?", {}, ""], [directoryPath() + "?x=1", {}, ""],
    [directoryPath("bad"), {}, ""], [directoryPath(), {"content-length": "8"}, "not-json"],
    [directoryPath(), {"transfer-encoding": "chunked"}, ""],
    [directoryPath(), {"transfer-encoding": "chunked"}, "not-json"],
  ] as const) {
    assertResponse(await request(address.port, "GET", path, {authorization: "Bearer token", ...headers}, body),
      400, {error: {code: "invalid_organization_shareable_join_request"}});
  }
  assertResponse(await request(address.port, "GET", directoryPath(), {authorization: "Bearer token"}, ""),
    503, {error: {code: "organization_shareable_join_unavailable"}});
  assert.equal(calls, 7);
});

test("directory empty results and stable errors share the existing family", async () => {
  for (const [code, status] of [
    [undefined, 200], ["invalid_organization_shareable_join_request", 400],
    ["organization_shareable_join_forbidden", 403], ["organization_shareable_join_unavailable", 503],
    ["unexpected", 503],
  ] as const) {
    const server = makeServer({...okStore(), listPending: async () => {
      if (code === "unexpected") throw new Error("sensitive");
      if (code !== undefined) throw new OrganizationShareableJoinApplicationStoreError(code);
      return {...directoryResult, applications: []};
    }});
    const address = await listen(server);
    const response = await request(address.port, "GET", directoryPath(), {authorization: "Bearer token"}, "");
    assertResponse(response, status, code === undefined ? {
      organization_shareable_join_application_directory_contract_id: "organization-shareable-join-application-directory:v1",
      organization_workspace_id: workspaceId, observed_at_utc: directoryResult.observedAtUtc, applications: [],
    } : {error: {code: code === "unexpected" ? "organization_shareable_join_unavailable" : code}});
    await close(server);
  }
});

test("directory GET waits for the store to settle before success or error", async () => {
  for (const rejects of [false, true]) {
    let release!: () => void;
    let started!: () => void;
    const gate = new Promise<void>((resolve) => {release = resolve;});
    const began = new Promise<void>((resolve) => {started = resolve;});
    const server = makeServer({...okStore(), listPending: async () => {
      started(); await gate;
      if (rejects) throw new Error("sensitive");
      return directoryResult;
    }});
    const address = await listen(server);
    let settled = false;
    const pending = request(address.port, "GET", directoryPath(), {authorization: "Bearer token"}, "")
      .then((result) => {settled = true; return result;});
    await began;
    assert.equal(settled, false);
    release();
    const response = await pending;
    assert.equal(response.status, rejects ? 503 : 200);
    assert.equal(response.headers["cache-control"], "no-store");
    await close(server);
  }
});
