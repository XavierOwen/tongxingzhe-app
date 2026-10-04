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
import {
  OrganizationDeletionRecoveryDirectoryStoreError,
} from "../src/organization-deletion-recovery-directory.js";
import { createBackendServer } from "../src/server.js";

const identity: VerifiedIdentity = {
  issuer: "https://recovery-route.synthetic/auth/v1",
  subject: "owner",
};
const item = {
  organizationWorkspaceId: "123e4567-e89b-12d3-a456-426614174001",
  deletionRequestId: "123e4567-e89b-12d3-a456-426614174002",
  displayName: "Deleted from ordinary directory",
  observedAtUtc: "2030-01-02T03:04:05.123Z",
  effectiveAtUtc: "2030-01-01T03:04:05.123Z",
  purgeAfterUtc: "2030-01-31T03:04:05.123Z",
  status: "deletion_pending" as const,
};

test("exact recovery GET authenticates, returns the fixed wire, and disables caching", async () => {
  let storeCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({ verify: async () => identity }),
    organizationDeletionRecoveryDirectoryStore: {
      async list(receivedIdentity) {
        storeCalls += 1;
        assert.deepEqual(receivedIdentity, identity);
        return [item];
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  assertResponse(
    await rawRequest(address.port, "GET", "/v1/organizations/deletion-recovery", {
      authorization: "Bearer token",
    }),
    200,
    {
      organization_deletion_recovery_directory_contract_id:
        "organization-deletion-recovery-directory:v1",
      items: [{
        organization_workspace_id: item.organizationWorkspaceId,
        deletion_request_id: item.deletionRequestId,
        display_name: item.displayName,
        observed_at_utc: item.observedAtUtc,
        effective_at_utc: item.effectiveAtUtc,
        purge_after_utc: item.purgeAfterUtc,
        status: "deletion_pending",
      }],
    },
  );
  assert.equal(storeCalls, 1);
});

test("raw aliases and wrong methods never reach recovery identity or store", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({
      verify: async () => {
        verifierCalls += 1;
        return identity;
      },
    }),
    organizationDeletionRecoveryDirectoryStore: {
      list: async () => {
        storeCalls += 1;
        return [];
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [method, path] of [
    ["PUT", "/v1/organizations/deletion-recovery"],
    ["POST", "/v1/organizations/deletion-recovery"],
    ["DELETE", "/v1/organizations/deletion-recovery"],
    ["GET", "/v1/organizations/deletion-recovery/"],
    ["GET", "/v1//organizations/deletion-recovery"],
    ["GET", "/v1/./organizations/deletion-recovery"],
    ["GET", "/v1/organizations/../organizations/deletion-recovery"],
    ["GET", "/v1/%6Frganizations/deletion-recovery"],
    ["GET", "/v1/organizations/deletion%2drecovery"],
    ["GET", "/v1/organizations/deletion-recovery/extra"],
  ] as const) {
    assertResponse(
      await rawRequest(address.port, method, path, { authorization: "Bearer token" }),
      404,
      { error: { code: "not_found" } },
    );
  }
  assert.equal(verifierCalls, 0);
  assert.equal(storeCalls, 0);
});

test("recovery GET authenticates before query/body checks and fails closed", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({
      verify: async (token) => {
        verifierCalls += 1;
        if (token === "invalid") throw new IdentityVerificationError("unauthenticated");
        if (token === "unavailable") throw new IdentityVerificationError("unavailable");
        return identity;
      },
    }),
    organizationDeletionRecoveryDirectoryStore: {
      list: async () => {
        storeCalls += 1;
        return [];
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  assertResponse(
    await rawRequest(address.port, "GET", "/v1/organizations/deletion-recovery?x=1", {
      "content-length": "1",
    }, "x"),
    401,
    { error: { code: "unauthenticated" } },
  );
  assert.equal(verifierCalls, 0);
  assertResponse(
    await rawRequest(address.port, "GET", "/v1/organizations/deletion-recovery?x=1", {
      authorization: "Bearer invalid",
      "content-length": "1",
    }, "x"),
    401,
    { error: { code: "unauthenticated" } },
  );
  assert.equal(storeCalls, 0);
  assertResponse(
    await rawRequest(address.port, "GET", "/v1/organizations/deletion-recovery?x=1", {
      authorization: "Bearer token",
    }),
    400,
    { error: { code: "invalid_organization_deletion_recovery_directory_request" } },
  );
  assert.equal(storeCalls, 0);

  assertResponse(
    await rawRequest(address.port, "GET", "/v1/organizations/deletion-recovery", {
      authorization: "Bearer unavailable",
    }),
    503,
    { error: { code: "organization_deletion_recovery_directory_unavailable" } },
  );
});

test("recovery GET maps identity denial and store failure without row details", async () => {
  for (const [error, status, code] of [
    [
      new OrganizationDeletionRecoveryDirectoryStoreError(
        "organization_deletion_recovery_directory_forbidden",
      ),
      403,
      "organization_deletion_recovery_directory_forbidden",
    ],
    [new Error("secret SQL row detail"), 503, "organization_deletion_recovery_directory_unavailable"],
  ] as const) {
    const server = createBackendServer({
      ...baseDependencies({ verify: async () => identity }),
      organizationDeletionRecoveryDirectoryStore: {
        list: async () => { throw error; },
      },
    });
    const address = await listen(server);
    test.after(() => close(server));
    const response = await rawRequest(
      address.port,
      "GET",
      "/v1/organizations/deletion-recovery",
      { authorization: "Bearer token" },
    );
    assertResponse(response, status, { error: { code } });
    assert.doesNotMatch(JSON.stringify(response.body), /secret|SQL|row detail/);
  }
});

function baseDependencies(identityVerifier: {
  verify(token: string): Promise<VerifiedIdentity>;
}) {
  return {
    identityVerifier,
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("SessionContext must not run for recovery directory tests");
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
    if (requestHeaders["transfer-encoding"] === undefined &&
      requestHeaders["content-length"] === undefined) {
      requestHeaders["content-length"] = String(Buffer.byteLength(body));
    }
    const request = httpRequest({
      host: "127.0.0.1",
      port,
      method,
      path,
      headers: requestHeaders,
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
