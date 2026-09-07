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
  OrganizationDirectedAccountInvitationStoreError,
  type OrganizationDirectedAccountInvitationAcceptResult,
  type OrganizationDirectedAccountInvitationCreateResult,
  type OrganizationDirectedAccountInvitationStore,
} from "../src/organization-directed-account-invitations.js";
import {createBackendServer} from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const invitationId = "123e4567-e89b-12d3-a456-426614174001";
const targetAppUserId = "123e4567-e89b-12d3-a456-426614174002";
const membershipId = "123e4567-e89b-12d3-a456-426614174003";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const createResult: OrganizationDirectedAccountInvitationCreateResult = {
  organizationInvitationContractId:
    "organization-directed-account-invitation:v1",
  invitationId,
  organizationWorkspaceId: workspaceId,
  issuedAtUtc: "2030-01-01T00:00:00.000Z",
  expiresAtUtc: "2030-01-08T00:00:00.000Z",
};
const acceptResult: OrganizationDirectedAccountInvitationAcceptResult = {
  organizationInvitationContractId:
    "organization-directed-account-invitation:v1",
  invitationId,
  organizationWorkspaceId: workspaceId,
  organizationMembershipId: membershipId,
  acceptedAtUtc: "2030-01-02T00:00:00.000Z",
};

test("raw invitation aliases return 404 before authentication or store access", async () => {
  let verifierCalls = 0;
  let createCalls = 0;
  let acceptCalls = 0;
  let organizationCreationIdentityCalls = 0;
  let organizationCreationStoreCalls = 0;
  const server = createBackendServer({
    ...unusedDependencies({
      verify: async () => {
        verifierCalls += 1;
        return identity;
      },
    }),
    organizationDirectedAccountInvitationStore: {
      create: async () => {
        createCalls += 1;
        return createResult;
      },
      accept: async () => {
        acceptCalls += 1;
        return acceptResult;
      },
    },
    organizationCreationIdentityVerifier: {
      verify: async () => {
        organizationCreationIdentityCalls += 1;
        throw new Error("organization creation identity must not run");
      },
    },
    organizationCreationStore: {
      create: async () => {
        organizationCreationStoreCalls += 1;
        throw new Error("organization creation store must not run");
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const paths = [
    ["PUT", createPath()],
    ["POST", `${createPath()}/`],
    ["POST", `/v1/organizations/${workspaceId}//directed-account-invitations`],
    ["POST", "/v1/organizations/./directed-account-invitations"],
    ["POST", "/v1/organizations/../directed-account-invitations"],
    ["POST", "/v1/organizations/%2e/directed-account-invitations"],
    ["POST", "/v1/organizations/%2E%2E/directed-account-invitations"],
    ["POST", "/v1/organizations/%41/directed-account-invitations"],
    ["POST", `/v1/organizations/${workspaceId}/directed-account-invitations/extra`],
    ["POST", `${createPath()}/../../../organizations`],
    ["GET", acceptPath()],
    ["POST", `${acceptPath()}/`],
    ["POST", `/v1/organization-directed-account-invitations//${invitationId}/accept`],
    ["POST", "/v1/organization-directed-account-invitations/./accept"],
    ["POST", "/v1/organization-directed-account-invitations/../accept"],
    ["POST", "/v1/organization-directed-account-invitations/%2e/accept"],
    ["POST", "/v1/organization-directed-account-invitations/%41/accept"],
    ["POST", `${acceptPath()}/extra`],
    ["POST", `${acceptPath()}/../../../organizations`],
    ["POST", "/v1/organization-directed-account-invitation/accept"],
  ] as const;

  for (const [method, path] of paths) {
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
  assert.equal(createCalls, 0);
  assert.equal(acceptCalls, 0);
  assert.equal(organizationCreationIdentityCalls, 0);
  assert.equal(organizationCreationStoreCalls, 0);
});

test("invitation routes authenticate before request and dependency checks", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...unusedDependencies({
      verify: async (token) => {
        verifierCalls += 1;
        if (token === "invalid") {
          throw new IdentityVerificationError("unauthenticated");
        }
        return identity;
      },
    }),
    organizationDirectedAccountInvitationStore: {
      create: async () => {
        storeCalls += 1;
        return createResult;
      },
      accept: async () => {
        storeCalls += 1;
        return acceptResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const path of [`${createPath()}?`, `${acceptPath()}?private=value`]) {
    const unauthenticated = await rawRequest(
      address.port,
      "POST",
      path,
      {authorization: "Bearer invalid"},
      "not-json",
    );
    assertResponse(unauthenticated, 401, {error: {code: "unauthenticated"}});

    const authenticated = await rawRequest(
      address.port,
      "POST",
      path,
      {authorization: "Bearer token"},
      "not-json",
    );
    assertResponse(authenticated, 400, {
      error: {code: "invalid_organization_invitation_request"},
    });
  }

  for (const path of [
    "/v1/organizations/not-a-uuid/directed-account-invitations",
    "/v1/organization-directed-account-invitations/not-a-uuid/accept",
  ]) {
    const response = await rawRequest(
      address.port,
      "POST",
      path,
      {authorization: "Bearer token"},
      "not-json",
    );
    assertResponse(response, 400, {
      error: {code: "invalid_organization_invitation_request"},
    });
  }

  assert.equal(verifierCalls, 6);
  assert.equal(storeCalls, 0);
});

test("create and accept routes use only their dedicated store methods", async () => {
  let createCalls = 0;
  let acceptCalls = 0;
  let receivedCreate:
    | Parameters<OrganizationDirectedAccountInvitationStore["create"]>
    | undefined;
  let receivedAccept:
    | Parameters<OrganizationDirectedAccountInvitationStore["accept"]>
    | undefined;
  const server = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationDirectedAccountInvitationStore: {
      create: async (...args) => {
        createCalls += 1;
        receivedCreate = args;
        return createResult;
      },
      accept: async (...args) => {
        acceptCalls += 1;
        receivedAccept = args;
        return acceptResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const created = await rawRequest(
    address.port,
    "POST",
    createPath(workspaceId.toUpperCase()),
    {authorization: "Bearer token"},
    JSON.stringify({
      invitation_id: invitationId.toUpperCase(),
      target_app_user_id: targetAppUserId.toUpperCase(),
    }),
  );
  assertResponse(created, 200, createWire());
  assert.deepEqual(receivedCreate, [
    identity,
    invitationId,
    workspaceId,
    targetAppUserId,
  ]);
  assert.equal(createCalls, 1);
  assert.equal(acceptCalls, 0);

  const accepted = await rawRequest(
    address.port,
    "POST",
    acceptPath(invitationId.toUpperCase()),
    {authorization: "Bearer token"},
    "{}",
  );
  assertResponse(accepted, 200, acceptWire());
  assert.deepEqual(receivedAccept, [identity, invitationId]);
  assert.equal(createCalls, 1);
  assert.equal(acceptCalls, 1);
});

test("invitation routes count chunked bytes at the inclusive 1 MiB limit", async () => {
  let createCalls = 0;
  const server = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationDirectedAccountInvitationStore: {
      create: async () => {
        createCalls += 1;
        return createResult;
      },
      accept: async () => acceptResult,
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const validBody = JSON.stringify({
    invitation_id: invitationId,
    target_app_user_id: targetAppUserId,
  });
  const oneMiBBody = validBody + " ".repeat(
    1024 * 1024 - Buffer.byteLength(validBody),
  );
  const accepted = await rawRequest(
    address.port,
    "POST",
    createPath(),
    {authorization: "Bearer token", "transfer-encoding": "chunked"},
    oneMiBBody,
  );
  assertResponse(accepted, 200, createWire());

  const tooLarge = await rawRequest(
    address.port,
    "POST",
    createPath(),
    {authorization: "Bearer token", "transfer-encoding": "chunked"},
    `${oneMiBBody} `,
  );
  assertResponse(tooLarge, 413, {error: {code: "payload_too_large"}});

  const multibyteTooLarge = await rawRequest(
    address.port,
    "POST",
    createPath(),
    {authorization: "Bearer token", "transfer-encoding": "chunked"},
    "界".repeat(Math.floor(1024 * 1024 / 3) + 1),
  );
  assertResponse(multibyteTooLarge, 413, {
    error: {code: "payload_too_large"},
  });
  assert.equal(createCalls, 1);
});

test("invitation routes reject invalid JSON and exact body drift", async () => {
  let storeCalls = 0;
  const server = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationDirectedAccountInvitationStore: {
      create: async () => {
        storeCalls += 1;
        return createResult;
      },
      accept: async () => {
        storeCalls += 1;
        return acceptResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const path of [createPath(), acceptPath()]) {
    for (const body of ["", "not-json"]) {
      const response = await rawRequest(
        address.port,
        "POST",
        path,
        {authorization: "Bearer token"},
        body,
      );
      assertResponse(response, 400, {error: {code: "invalid_json"}});
    }
  }

  const invalidRequests = [
    [createPath(), "{}"],
    [createPath(), JSON.stringify({invitation_id: invitationId})],
    [createPath(), JSON.stringify({
      invitation_id: invitationId,
      target_app_user_id: targetAppUserId,
      actor: "forbidden-extra",
    })],
    [createPath(), JSON.stringify({
      invitation_id: "not-a-uuid",
      target_app_user_id: targetAppUserId,
    })],
    [createPath(), "[]"],
    [acceptPath(), JSON.stringify({invitation_id: invitationId})],
    [acceptPath(), "[]"],
  ] as const;
  for (const [path, body] of invalidRequests) {
    const response = await rawRequest(
      address.port,
      "POST",
      path,
      {authorization: "Bearer token"},
      body,
    );
    assertResponse(response, 400, {
      error: {code: "invalid_organization_invitation_request"},
    });
  }
  assert.equal(storeCalls, 0);
});

test("invitation routes stop before body parsing when dependencies are missing", async () => {
  const missingVerifierServer = createBackendServer({
    ...unusedDependencies(undefined as never),
    organizationDirectedAccountInvitationStore: successfulStore,
  });
  const missingVerifierAddress = await listen(missingVerifierServer);
  test.after(() => close(missingVerifierServer));
  await assertInvitationError(
    missingVerifierAddress.port,
    createPath(),
    {authorization: "Bearer token"},
    "not-json",
    503,
    "organization_invitation_unavailable",
  );

  const missingStoreServer = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
  });
  const missingStoreAddress = await listen(missingStoreServer);
  test.after(() => close(missingStoreServer));
  await assertInvitationError(
    missingStoreAddress.port,
    acceptPath(),
    {authorization: "Bearer token"},
    "not-json",
    503,
    "organization_invitation_unavailable",
  );
});

test("invitation routes wait for store completion before responding", async () => {
  let releaseStore: (() => void) | undefined;
  let markStoreStarted: (() => void) | undefined;
  const storeStarted = new Promise<void>((resolve) => {
    markStoreStarted = resolve;
  });
  const server = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationDirectedAccountInvitationStore: {
      create: async () => createResult,
      async accept() {
        markStoreStarted?.();
        await new Promise<void>((resolve) => {
          releaseStore = resolve;
        });
        return acceptResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  let responseSettled = false;
  const responsePromise = rawRequest(
    address.port,
    "POST",
    acceptPath(),
    {authorization: "Bearer token"},
    "{}",
  ).then((response) => {
    responseSettled = true;
    return response;
  });
  await storeStarted;
  assert.equal(responseSettled, false);
  releaseStore?.();

  assertResponse(await responsePromise, 200, acceptWire());
});

test("invitation routes return exact redacted dependency and store errors", async () => {
  const missingBearerServer = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationDirectedAccountInvitationStore: successfulStore,
  });
  const missingBearerAddress = await listen(missingBearerServer);
  test.after(() => close(missingBearerServer));
  await assertInvitationError(
    missingBearerAddress.port,
    createPath(),
    {},
    createBody(invitationId),
    401,
    "unauthenticated",
  );

  const verifierFailureServer = createBackendServer({
    ...unusedDependencies({
      verify: async (token) => {
        if (token === "unavailable") {
          throw new IdentityVerificationError("unavailable");
        }
        throw new Error("provider secret");
      },
    }),
    organizationDirectedAccountInvitationStore: successfulStore,
  });
  const verifierFailureAddress = await listen(verifierFailureServer);
  test.after(() => close(verifierFailureServer));
  for (const token of ["unavailable", "unknown"]) {
    await assertInvitationError(
      verifierFailureAddress.port,
      createPath(),
      {authorization: `Bearer ${token}`},
      createBody(invitationId),
      503,
      "organization_invitation_unavailable",
    );
  }

  const typedCases = [
    [
      "123e4567-e89b-12d3-a456-426614174010",
      400,
      "invalid_organization_invitation_request",
    ],
    [
      "123e4567-e89b-12d3-a456-426614174011",
      403,
      "organization_invitation_forbidden",
    ],
    [
      "123e4567-e89b-12d3-a456-426614174012",
      409,
      "organization_invitation_conflict",
    ],
    [
      "123e4567-e89b-12d3-a456-426614174013",
      503,
      "organization_invitation_unavailable",
    ],
  ] as const;
  const unknownId = "123e4567-e89b-12d3-a456-426614174014";
  let createCalls = 0;
  let acceptCalls = 0;
  const storeFailureServer = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationDirectedAccountInvitationStore: {
      create: async (_identity, receivedId) => {
        createCalls += 1;
        const entry = typedCases.find(([id]) => id === receivedId);
        if (entry !== undefined) {
          throw new OrganizationDirectedAccountInvitationStoreError(entry[2]);
        }
        throw new Error("database SQL and identity secret");
      },
      accept: async (_identity, receivedId) => {
        acceptCalls += 1;
        const entry = typedCases.find(([id]) => id === receivedId);
        if (entry !== undefined) {
          throw new OrganizationDirectedAccountInvitationStoreError(entry[2]);
        }
        throw new Error("database SQL and identity secret");
      },
    },
  });
  const storeFailureAddress = await listen(storeFailureServer);
  test.after(() => close(storeFailureServer));

  for (const [id, status, code] of typedCases) {
    await assertInvitationError(
      storeFailureAddress.port,
      createPath(),
      {authorization: "Bearer token"},
      createBody(id),
      status,
      code,
    );
  }
  await assertInvitationError(
    storeFailureAddress.port,
    createPath(),
    {authorization: "Bearer token"},
    createBody(unknownId),
    503,
    "organization_invitation_unavailable",
  );
  for (const [id, status, code] of typedCases) {
    await assertInvitationError(
      storeFailureAddress.port,
      acceptPath(id),
      {authorization: "Bearer token"},
      "{}",
      status,
      code,
    );
  }
  await assertInvitationError(
    storeFailureAddress.port,
    acceptPath(unknownId),
    {authorization: "Bearer token"},
    "{}",
    503,
    "organization_invitation_unavailable",
  );
  assert.equal(createCalls, typedCases.length + 1);
  assert.equal(acceptCalls, typedCases.length + 1);
});

const successfulStore: OrganizationDirectedAccountInvitationStore = {
  create: async () => createResult,
  accept: async () => acceptResult,
};

function createPath(value = workspaceId): string {
  return `/v1/organizations/${value}/directed-account-invitations`;
}

function acceptPath(value = invitationId): string {
  return `/v1/organization-directed-account-invitations/${value}/accept`;
}

function createBody(value: string): string {
  return JSON.stringify({
    invitation_id: value,
    target_app_user_id: targetAppUserId,
  });
}

function createWire(): Readonly<Record<string, unknown>> {
  return {
    organization_invitation_contract_id:
      "organization-directed-account-invitation:v1",
    invitation_id: invitationId,
    organization_workspace_id: workspaceId,
    issued_at_utc: createResult.issuedAtUtc,
    expires_at_utc: createResult.expiresAtUtc,
  };
}

function acceptWire(): Readonly<Record<string, unknown>> {
  return {
    organization_invitation_contract_id:
      "organization-directed-account-invitation:v1",
    invitation_id: invitationId,
    organization_workspace_id: workspaceId,
    organization_membership_id: membershipId,
    accepted_at_utc: acceptResult.acceptedAtUtc,
  };
}

function unusedDependencies(
  identityVerifier: {
    verify(token: string): Promise<VerifiedIdentity>;
  },
) {
  return {
    identityVerifier,
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("SessionContext must not run for invitation tests");
      },
    },
  };
}

async function assertInvitationError(
  port: number,
  path: string,
  headers: Readonly<Record<string, string>>,
  body: string,
  status: number,
  code: string,
): Promise<void> {
  const response = await rawRequest(port, "POST", path, headers, body);
  assertResponse(response, status, {error: {code}});
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
