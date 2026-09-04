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
  OrganizationOwnerTransferStoreError,
  type OrganizationOwnerTransferResult,
  type OrganizationOwnerTransferStore,
} from "../src/organization-owner-transfer.js";
import {createBackendServer} from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const requestId = "123e4567-e89b-12d3-a456-426614174001";
const targetMembershipId = "123e4567-e89b-12d3-a456-426614174002";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const transferResult: OrganizationOwnerTransferResult = {
  ownerTransferContractId: "organization-owner-transfer:v1",
  organizationWorkspaceId: workspaceId,
  previousOwnerAssignmentId: "123e4567-e89b-12d3-a456-426614174003",
  organizationOwnerAssignmentId: "123e4567-e89b-12d3-a456-426614174004",
  effectiveAtUtc: "2030-01-01T00:00:00.000Z",
};

test("raw owner-transfer aliases return 404 before authentication", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...unusedDependencies({
      verify: async () => {
        verifierCalls += 1;
        return identity;
      },
    }),
    organizationOwnerTransferStore: {
      transfer: async () => {
        storeCalls += 1;
        return transferResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const paths = [
    ["PUT", `/v1/organizations/${workspaceId}/owner-transfer`],
    ["POST", `/v1/organizations/${workspaceId}/owner-transfer/`],
    ["POST", `/v1/organizations/${workspaceId}//owner-transfer`],
    ["POST", "/v1/organizations/./owner-transfer"],
    ["POST", "/v1/organizations/../owner-transfer"],
    ["POST", "/v1/organizations/%2e/owner-transfer"],
    ["POST", "/v1/organizations/%2E%2E/owner-transfer"],
    ["POST", "/v1/organizations/%41/owner-transfer"],
    ["POST", "/v1/organizations/%2F/owner-transfer"],
    ["POST", `/v1/organizations/${workspaceId}/owner-transfer/extra`],
    ["POST", "/v1/organization/owner-transfer"],
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
  assert.equal(storeCalls, 0);
});

test("owner-transfer authenticates before query and path validation", async () => {
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
    organizationOwnerTransferStore: {
      transfer: async () => {
        storeCalls += 1;
        return transferResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const unauthenticatedQuery = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/owner-transfer?`,
    {authorization: "Bearer invalid"},
    "not-json",
  );
  assertResponse(unauthenticatedQuery, 401, {
    error: {code: "unauthenticated"},
  });

  const authenticatedBareQuery = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/owner-transfer?`,
    {authorization: "Bearer token"},
    "not-json",
  );
  assertResponse(authenticatedBareQuery, 400, {
    error: {code: "invalid_organization_owner_transfer_request"},
  });

  const authenticatedQuery = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/owner-transfer?private=value`,
    {authorization: "Bearer token"},
    "not-json",
  );
  assertResponse(authenticatedQuery, 400, {
    error: {code: "invalid_organization_owner_transfer_request"},
  });

  const malformedPath = await rawRequest(
    address.port,
    "POST",
    "/v1/organizations/not-a-uuid/owner-transfer",
    {authorization: "Bearer token"},
    "not-json",
  );
  assertResponse(malformedPath, 400, {
    error: {code: "invalid_organization_owner_transfer_request"},
  });

  assert.equal(verifierCalls, 4);
  assert.equal(storeCalls, 0);
});

test("owner-transfer uses chunked actual bytes at the inclusive 1 MiB limit", async () => {
  let storeCalls = 0;
  let received: Parameters<OrganizationOwnerTransferStore["transfer"]> | undefined;
  const server = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationOwnerTransferStore: {
      transfer: async (...args) => {
        storeCalls += 1;
        received = args;
        return transferResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const validBody = JSON.stringify({
    request_id: requestId.toUpperCase(),
    target_organization_membership_id: targetMembershipId.toUpperCase(),
  });
  const oneMiBBody = validBody + " ".repeat(
    1024 * 1024 - Buffer.byteLength(validBody),
  );
  const accepted = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId.toUpperCase()}/owner-transfer`,
    {
      authorization: "Bearer token",
      "transfer-encoding": "chunked",
    },
    oneMiBBody,
  );
  assertResponse(accepted, 200, {
    owner_transfer_contract_id: "organization-owner-transfer:v1",
    organization_workspace_id: workspaceId,
    previous_owner_assignment_id: transferResult.previousOwnerAssignmentId,
    organization_owner_assignment_id:
      transferResult.organizationOwnerAssignmentId,
    effective_at_utc: transferResult.effectiveAtUtc,
  });
  assert.deepEqual(received, [
    identity,
    requestId,
    workspaceId,
    targetMembershipId,
  ]);

  const tooLarge = await rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/owner-transfer`,
    {
      authorization: "Bearer token",
      "transfer-encoding": "chunked",
    },
    `${oneMiBBody} `,
  );
  assertResponse(tooLarge, 413, {error: {code: "payload_too_large"}});
  assert.equal(storeCalls, 1);

  for (const body of ["", "not-json"] as const) {
    const invalid = await rawRequest(
      address.port,
      "POST",
      `/v1/organizations/${workspaceId}/owner-transfer`,
      {authorization: "Bearer token"},
      body,
    );
    assertResponse(invalid, 400, {error: {code: "invalid_json"}});
  }
  assert.equal(storeCalls, 1);
});

test("owner-transfer waits for the store promise before responding", async () => {
  let releaseStore: (() => void) | undefined;
  let markStoreStarted: (() => void) | undefined;
  const storeStarted = new Promise<void>((resolve) => {
    markStoreStarted = resolve;
  });
  const server = createBackendServer({
    ...unusedDependencies({verify: async () => identity}),
    organizationOwnerTransferStore: {
      async transfer() {
        markStoreStarted?.();
        await new Promise<void>((resolve) => {
          releaseStore = resolve;
        });
        return transferResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  let responseSettled = false;
  const responsePromise = rawRequest(
    address.port,
    "POST",
    `/v1/organizations/${workspaceId}/owner-transfer`,
    {authorization: "Bearer token"},
    JSON.stringify({
      request_id: requestId,
      target_organization_membership_id: targetMembershipId,
    }),
  ).then((response) => {
    responseSettled = true;
    return response;
  });
  await storeStarted;
  assert.equal(responseSettled, false);
  releaseStore?.();

  const response = await responsePromise;
  assertResponse(response, 200, {
    owner_transfer_contract_id: "organization-owner-transfer:v1",
    organization_workspace_id: workspaceId,
    previous_owner_assignment_id: transferResult.previousOwnerAssignmentId,
    organization_owner_assignment_id:
      transferResult.organizationOwnerAssignmentId,
    effective_at_utc: transferResult.effectiveAtUtc,
  });
});

test("owner-transfer keeps stable dependency, body, and store errors exact", async () => {
  const missingBearerServer = createTestServer();
  const missingBearerAddress = await listen(missingBearerServer);
  test.after(() => close(missingBearerServer));
  await assertOwnerTransferError(
    missingBearerAddress.port,
    {},
    requestBodyFor(requestId),
    401,
    "unauthenticated",
  );

  const missingVerifierServer = createTestServer({missingVerifier: true});
  const missingVerifierAddress = await listen(missingVerifierServer);
  test.after(() => close(missingVerifierServer));
  await assertOwnerTransferError(
    missingVerifierAddress.port,
    {authorization: "Bearer token"},
    requestBodyFor(requestId),
    503,
    "organization_owner_transfer_unavailable",
  );

  const missingStoreServer = createTestServer({missingStore: true});
  const missingStoreAddress = await listen(missingStoreServer);
  test.after(() => close(missingStoreServer));
  await assertOwnerTransferError(
    missingStoreAddress.port,
    {authorization: "Bearer token"},
    requestBodyFor(requestId),
    503,
    "organization_owner_transfer_unavailable",
  );

  const verifierFailureServer = createTestServer({
    identityVerifier: {
      verify: async (token) => {
        if (token === "unavailable") {
          throw new IdentityVerificationError("unavailable");
        }
        if (token === "unknown") {
          throw new Error("provider secret");
        }
        return identity;
      },
    },
  });
  const verifierFailureAddress = await listen(verifierFailureServer);
  test.after(() => close(verifierFailureServer));
  for (const token of ["unavailable", "unknown"] as const) {
    await assertOwnerTransferError(
      verifierFailureAddress.port,
      {authorization: `Bearer ${token}`},
      requestBodyFor(requestId),
      503,
      "organization_owner_transfer_unavailable",
    );
  }

  let strictBodyStoreCalls = 0;
  const strictBodyServer = createTestServer({
    transferStore: {
      transfer: async () => {
        strictBodyStoreCalls += 1;
        return transferResult;
      },
    },
  });
  const strictBodyAddress = await listen(strictBodyServer);
  test.after(() => close(strictBodyServer));
  const strictBodies = [
    JSON.stringify({request_id: requestId}),
    JSON.stringify({
      request_id: requestId,
      target_organization_membership_id: targetMembershipId,
      extra: true,
    }),
    JSON.stringify([]),
  ] as const;
  for (const body of strictBodies) {
    await assertOwnerTransferError(
      strictBodyAddress.port,
      {authorization: "Bearer token"},
      body,
      400,
      "invalid_organization_owner_transfer_request",
    );
  }
  assert.equal(strictBodyStoreCalls, 0);

  const typedStoreCases = [
    {
      requestId: "123e4567-e89b-12d3-a456-426614174010",
      status: 403,
      storeCode: "organization_owner_transfer_forbidden",
    },
    {
      requestId: "123e4567-e89b-12d3-a456-426614174011",
      status: 409,
      storeCode: "organization_owner_transfer_conflict",
    },
    {
      requestId: "123e4567-e89b-12d3-a456-426614174012",
      status: 409,
      storeCode: "organization_owner_transfer_target_already_owner",
    },
    {
      requestId: "123e4567-e89b-12d3-a456-426614174013",
      status: 503,
      storeCode: "organization_owner_transfer_unavailable",
    },
    {
      requestId: "123e4567-e89b-12d3-a456-426614174014",
      status: 400,
      storeCode: "invalid_organization_owner_transfer_request",
    },
  ] as const;
  const unknownStoreRequestId = "123e4567-e89b-12d3-a456-426614174015";
  let storeCalls = 0;
  const typedStoreServer = createTestServer({
    transferStore: {
      transfer: async (_identity, storeRequestId) => {
        storeCalls += 1;
        const typedCase = typedStoreCases.find(({requestId: candidate}) =>
          candidate === storeRequestId
        );
        if (typedCase !== undefined) {
          throw new OrganizationOwnerTransferStoreError(typedCase.storeCode);
        }
        if (storeRequestId === unknownStoreRequestId) {
          throw new Error("database secret");
        }
        return transferResult;
      },
    },
  });
  const typedStoreAddress = await listen(typedStoreServer);
  test.after(() => close(typedStoreServer));
  for (const typedCase of typedStoreCases) {
    await assertOwnerTransferError(
      typedStoreAddress.port,
      {authorization: "Bearer token"},
      requestBodyFor(typedCase.requestId),
      typedCase.status,
      typedCase.storeCode,
    );
  }
  await assertOwnerTransferError(
    typedStoreAddress.port,
    {authorization: "Bearer token"},
    requestBodyFor(unknownStoreRequestId),
    503,
    "organization_owner_transfer_unavailable",
  );
  assert.equal(storeCalls, typedStoreCases.length + 1);
});

type TestIdentityVerifier = {
  verify(token: string): Promise<VerifiedIdentity>;
};

const successfulTransferStore: OrganizationOwnerTransferStore = {
  transfer: async () => transferResult,
};

function createTestServer(options: {
  readonly identityVerifier?: TestIdentityVerifier;
  readonly transferStore?: OrganizationOwnerTransferStore;
  readonly missingVerifier?: boolean;
  readonly missingStore?: boolean;
} = {}): Server {
  const verifier = options.identityVerifier ?? {
    verify: async () => identity,
  };
  const dependencies = {
    ...unusedDependencies(verifier),
    ...(options.missingStore
      ? {}
      : {
        organizationOwnerTransferStore:
          options.transferStore ?? successfulTransferStore,
      }),
  };
  return options.missingVerifier
    ? createBackendServer({...dependencies, identityVerifier: undefined as never})
    : createBackendServer(dependencies);
}

function requestBodyFor(value: string): string {
  return JSON.stringify({
    request_id: value,
    target_organization_membership_id: targetMembershipId,
  });
}

async function assertOwnerTransferError(
  port: number,
  headers: Readonly<Record<string, string>>,
  body: string,
  status: number,
  code: string,
): Promise<void> {
  const response = await rawRequest(
    port,
    "POST",
    `/v1/organizations/${workspaceId}/owner-transfer`,
    headers,
    body,
  );
  assertResponse(response, status, {error: {code}});
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
        throw new Error("context must not run for owner transfer tests");
      },
    },
  };
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
