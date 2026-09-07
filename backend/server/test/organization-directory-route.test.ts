import assert from "node:assert/strict";
import {
  request as httpRequest,
  type IncomingHttpHeaders,
  type Server,
} from "node:http";
import type { AddressInfo } from "node:net";
import test from "node:test";

import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";
import { OrganizationDirectoryStoreError } from "../src/organization-directory.js";
import { createBackendServer } from "../src/server.js";

const identity: VerifiedIdentity = {
  issuer: "https://directory-route.synthetic/auth/v1",
  subject: "active-member",
};
const workspaceId = "123e4567-e89b-12d3-a456-426614174001";
const creationRequestId = "123e4567-e89b-12d3-a456-426614174010";

test("organization directory waits for PostgreSQL before returning its exact wire", async () => {
  let releaseList: (() => void) | undefined;
  let markListStarted: (() => void) | undefined;
  const listStarted = new Promise<void>((resolve) => {
    markListStarted = resolve;
  });
  const listGate = new Promise<void>((resolve) => {
    releaseList = resolve;
  });
  let storeCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({ verify: async () => identity }),
    organizationDirectoryStore: {
      async list(receivedIdentity) {
        storeCalls += 1;
        assert.deepEqual(receivedIdentity, identity);
        markListStarted?.();
        await listGate;
        return [{
          organizationWorkspaceId: workspaceId,
          organizationName: "   同行者   ",
        }];
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  let responseSettled = false;
  const responsePromise = rawRequest(
    address.port,
    "GET",
    "/v1/organizations",
    { authorization: "Bearer access-token", "content-length": "0" },
  ).then((response) => {
    responseSettled = true;
    return response;
  });
  await listStarted;
  assert.equal(responseSettled, false);
  assert.equal(storeCalls, 1);
  releaseList?.();

  assertResponse(await responsePromise, 200, {
    organization_directory_contract_id: "organization-directory:v1",
    organizations: [{
      organization_workspace_id: workspaceId,
      organization_name: "   同行者   ",
    }],
  });
});

test("organization directory raw aliases return 404 without authentication", async () => {
  let genericVerifierCalls = 0;
  let directoryStoreCalls = 0;
  let creationVerifierCalls = 0;
  let creationStoreCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({
      verify: async () => {
        genericVerifierCalls += 1;
        return identity;
      },
    }),
    organizationDirectoryStore: {
      list: async () => {
        directoryStoreCalls += 1;
        return [];
      },
    },
    organizationCreationIdentityVerifier: {
      verify: async () => {
        creationVerifierCalls += 1;
        throw new Error("creation verifier must not run");
      },
    },
    organizationCreationStore: {
      create: async () => {
        creationStoreCalls += 1;
        throw new Error("creation store must not run");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const targets = [
    ["PUT", "/v1/organizations"],
    ["PATCH", "/v1/organizations"],
    ["DELETE", "/v1/organizations"],
    ["GET", "/v1/organizations/"],
    ["POST", "/v1/organizations/"],
    ["GET", "/v1//organizations"],
    ["GET", "/v1/./organizations"],
    ["GET", "/v1/other/../organizations"],
    ["GET", "/v1/%2e/organizations"],
    ["GET", "/v1/%2E%2E/v1/organizations"],
    ["GET", "/v1/%6Frganizations"],
    ["GET", "/v1/organizations%2f"],
    ["GET", "/v1/organization"],
    ["GET", "/v1/organizations/extra"],
  ] as const;

  for (const [method, path] of targets) {
    assertResponse(
      await rawRequest(
        address.port,
        method,
        path,
        { authorization: "Bearer access-token" },
        "not-json",
      ),
      404,
      { error: { code: "not_found" } },
    );
  }
  assert.equal(genericVerifierCalls, 0);
  assert.equal(directoryStoreCalls, 0);
  assert.equal(creationVerifierCalls, 0);
  assert.equal(creationStoreCalls, 0);
});

test("organization directory authenticates before raw query and body declarations", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({
      verify: async (token) => {
        verifierCalls += 1;
        if (token === "invalid") {
          throw new IdentityVerificationError("unauthenticated");
        }
        if (token === "unavailable") {
          throw new IdentityVerificationError("unavailable");
        }
        if (token === "unknown") {
          throw new Error("provider secret");
        }
        return identity;
      },
    }),
    organizationDirectoryStore: {
      list: async () => {
        storeCalls += 1;
        return [];
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  assertResponse(
    await rawRequest(
      address.port,
      "GET",
      "/v1/organizations?private=value",
      { "content-length": "1" },
      "x",
    ),
    401,
    { error: { code: "unauthenticated" } },
  );
  assert.equal(verifierCalls, 0);

  for (const authorization of [
    "Basic token",
    "Bearer",
    "Bearer  token",
    "Bearer token extra",
    "Bearer token,second",
  ]) {
    assertResponse(
      await rawRequest(
        address.port,
        "GET",
        "/v1/organizations?private=value",
        { authorization, "content-length": "1" },
        "x",
      ),
      401,
      { error: { code: "unauthenticated" } },
    );
  }
  assert.equal(verifierCalls, 0);

  for (const [token, status, code] of [
    ["invalid", 401, "unauthenticated"],
    ["unavailable", 503, "organization_directory_unavailable"],
    ["unknown", 503, "organization_directory_unavailable"],
  ] as const) {
    assertResponse(
      await rawRequest(
        address.port,
        "GET",
        "/v1/organizations?private=value",
        {
          authorization: `Bearer ${token}`,
          "content-length": "1",
        },
        "x",
      ),
      status,
      { error: { code } },
    );
  }
  assert.equal(storeCalls, 0);

  for (const [path, headers, body] of [
    ["/v1/organizations?", {}, ""],
    ["/v1/organizations?private=value", {}, ""],
    ["/v1/organizations", { "content-length": "1" }, "x"],
    ["/v1/organizations", { "content-length": "00" }, ""],
    ["/v1/organizations", { "transfer-encoding": "chunked" }, ""],
  ] as const) {
    assertResponse(
      await rawRequest(
        address.port,
        "GET",
        path,
        { authorization: "Bearer access-token", ...headers },
        body,
      ),
      400,
      { error: { code: "invalid_organization_directory_request" } },
    );
  }
  assert.equal(storeCalls, 0);
});

test("organization directory returns exact unavailable and forbidden errors", async () => {
  const missingStoreServer = createBackendServer(
    baseDependencies({ verify: async () => identity }),
  );
  const missingStoreAddress = await listen(missingStoreServer);
  test.after(() => close(missingStoreServer));
  assertResponse(
    await rawRequest(
      missingStoreAddress.port,
      "GET",
      "/v1/organizations",
      { authorization: "Bearer token" },
    ),
    503,
    { error: { code: "organization_directory_unavailable" } },
  );

  const forbiddenServer = createBackendServer({
    ...baseDependencies({ verify: async () => identity }),
    organizationDirectoryStore: {
      list: async () => {
        throw new OrganizationDirectoryStoreError(
          "organization_directory_forbidden",
        );
      },
    },
  });
  const forbiddenAddress = await listen(forbiddenServer);
  test.after(() => close(forbiddenServer));
  assertResponse(
    await rawRequest(
      forbiddenAddress.port,
      "GET",
      "/v1/organizations",
      { authorization: "Bearer token" },
    ),
    403,
    { error: { code: "organization_directory_forbidden" } },
  );
});

test("organization directory GET leaves the existing organization POST unchanged", async () => {
  let genericVerifierCalls = 0;
  let directoryStoreCalls = 0;
  let creationVerifierCalls = 0;
  let creationStoreCalls = 0;
  const creationIdentity = {
    issuer: identity.issuer,
    subject: "creator",
    purpose: "organization_creation" as const,
  };
  const server = createBackendServer({
    ...baseDependencies({
      verify: async () => {
        genericVerifierCalls += 1;
        throw new Error("generic verifier must not handle POST");
      },
    }),
    organizationDirectoryStore: {
      list: async () => {
        directoryStoreCalls += 1;
        return [];
      },
    },
    organizationCreationIdentityVerifier: {
      verify: async () => {
        creationVerifierCalls += 1;
        return creationIdentity;
      },
    },
    organizationCreationStore: {
      create: async (receivedIdentity, requestId, displayName) => {
        creationStoreCalls += 1;
        assert.deepEqual(receivedIdentity, creationIdentity);
        assert.equal(requestId, creationRequestId);
        assert.equal(displayName, "Organization");
        return {
          creationContractId: "organization-creation:v1",
          organizationWorkspaceId: workspaceId,
          organizationMembershipId: "123e4567-e89b-12d3-a456-426614174002",
          organizationOwnerAssignmentId:
            "123e4567-e89b-12d3-a456-426614174003",
          createdAtUtc: "2030-01-02T03:04:05.678Z",
        };
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  assertResponse(
    await rawRequest(
      address.port,
      "POST",
      "/v1/organizations",
      {
        authorization: "Bearer creation-token",
        "content-type": "application/json",
      },
      JSON.stringify({
        request_id: creationRequestId,
        display_name: "Organization",
      }),
    ),
    200,
    {
      creation_contract_id: "organization-creation:v1",
      organization_workspace_id: workspaceId,
      organization_membership_id: "123e4567-e89b-12d3-a456-426614174002",
      organization_owner_assignment_id:
        "123e4567-e89b-12d3-a456-426614174003",
      created_at_utc: "2030-01-02T03:04:05.678Z",
    },
  );
  assert.equal(genericVerifierCalls, 0);
  assert.equal(directoryStoreCalls, 0);
  assert.equal(creationVerifierCalls, 1);
  assert.equal(creationStoreCalls, 1);
});

function baseDependencies(identityVerifier: {
  verify(token: string): Promise<VerifiedIdentity>;
}) {
  return {
    identityVerifier,
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("SessionContext must not run for directory tests");
      },
    },
  };
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
  body = "",
): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const requestHeaders = { ...headers };
    if (
      requestHeaders["transfer-encoding"] === undefined &&
      requestHeaders["content-length"] === undefined
    ) {
      requestHeaders["content-length"] = String(Buffer.byteLength(body));
    }
    const request = httpRequest(
      {
        host: "127.0.0.1",
        port,
        method,
        path,
        headers: requestHeaders,
      },
      (response) => {
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
      },
    );
    request.on("error", reject);
    request.end(body);
  });
}

function assertResponse(
  response: RawResponse,
  status: number,
  body: unknown,
): void {
  assert.equal(response.status, status);
  assert.equal(
    response.headers["content-type"],
    "application/json; charset=utf-8",
  );
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
