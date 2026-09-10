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
  OrganizationShareableJoinLinkStoreError,
  type OrganizationShareableJoinLinkCreateResult,
  type OrganizationShareableJoinLinkPreviewResult,
  type OrganizationShareableJoinLinkStore,
} from "../src/organization-shareable-join-links.js";
import {createBackendServer} from "../src/server.js";

const workspaceId = "123e4567-e89b-12d3-a456-426614174000";
const linkId = "123e4567-e89b-12d3-a456-426614174001";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const createResult: OrganizationShareableJoinLinkCreateResult = {
  organizationShareableJoinLinkContractId:
    "organization-shareable-join-link:v1",
  linkId,
  organizationWorkspaceId: workspaceId,
  issuedAtUtc: "2030-01-01T00:00:00.000Z",
  expiresAtUtc: "2030-01-08T00:00:00.000Z",
};
const previewResult: OrganizationShareableJoinLinkPreviewResult = {
  organizationShareableJoinLinkPreviewContractId:
    "organization-shareable-join-link-preview:v1",
  linkId,
  organizationName: " 同行组织 ",
  expiresAtUtc: createResult.expiresAtUtc,
};

test("shareable link routes return their exact bound receipts", async () => {
  let createArgs:
    | Parameters<OrganizationShareableJoinLinkStore["create"]>
    | undefined;
  let previewArgs:
    | Parameters<OrganizationShareableJoinLinkStore["preview"]>
    | undefined;
  const server = createBackendServer({
    ...baseDependencies({verify: async () => identity}),
    organizationShareableJoinLinkStore: {
      create: async (...args) => {
        createArgs = args;
        return createResult;
      },
      preview: async (...args) => {
        previewArgs = args;
        return previewResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  assertResponse(
    await rawRequest(
      address.port,
      "POST",
      createPath(workspaceId.toUpperCase()),
      {authorization: "Bearer token"},
      JSON.stringify({link_id: linkId.toUpperCase()}),
    ),
    200,
    createWire(),
  );
  assert.deepEqual(createArgs, [identity, linkId, workspaceId]);

  assertResponse(
    await rawRequest(
      address.port,
      "GET",
      previewPath(linkId.toUpperCase()),
      {authorization: "Bearer token", "content-length": "0"},
      "",
      false,
    ),
    200,
    previewWire(),
  );
  assert.deepEqual(previewArgs, [identity, linkId]);
});

test("raw aliases and wrong methods return 404 before authentication", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({
      verify: async () => {
        verifierCalls += 1;
        return identity;
      },
    }),
    organizationShareableJoinLinkStore: {
      create: async () => {
        storeCalls += 1;
        return createResult;
      },
      preview: async () => {
        storeCalls += 1;
        return previewResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const targets = [
    ["GET", createPath()],
    ["PUT", createPath()],
    ["POST", `${createPath()}/`],
    ["POST", `/v1/organizations/${workspaceId}//shareable-join-links`],
    ["POST", "/v1/organizations/./shareable-join-links"],
    ["POST", "/v1/organizations/../shareable-join-links"],
    ["POST", "/v1/organizations/%2e/shareable-join-links"],
    ["POST", `/v1/organizations/%31${workspaceId.slice(1)}/shareable-join-links`],
    ["POST", `${createPath()}/../../../organizations`],
    ["POST", previewPath()],
    ["HEAD", previewPath()],
    ["PUT", previewPath()],
    ["DELETE", previewPath()],
    ["GET", `${previewPath()}/`],
    ["GET", "/v1/organization-shareable-join-links/."],
    ["GET", "/v1/organization-shareable-join-links/.."],
    ["GET", "/v1/organization-shareable-join-links/%2e"],
    ["GET", `/v1/organization-shareable-join-links/%31${linkId.slice(1)}`],
    ["GET", `${previewPath()}/extra`],
    ["GET", `${previewPath()}/../../organizations`],
  ] as const;
  for (const [method, path] of targets) {
    assertResponse(
      await rawRequest(
        address.port,
        method,
        path,
        {authorization: "Bearer token"},
        "not-json",
      ),
      404,
      method === "HEAD" ? undefined : {error: {code: "not_found"}},
    );
  }
  assert.equal(verifierCalls, 0);
  assert.equal(storeCalls, 0);
});

test("shareable link routes authenticate before request and dependency checks", async () => {
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
    organizationShareableJoinLinkStore: {
      create: async () => {
        storeCalls += 1;
        return createResult;
      },
      preview: async () => {
        storeCalls += 1;
        return previewResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [method, path] of [
    ["POST", `${createPath("not-a-uuid")}?private=value`],
    ["GET", `${previewPath("not-a-uuid")}?private=value`],
  ] as const) {
    assertResponse(
      await rawRequest(address.port, method, path, {}, "not-json"),
      401,
      {error: {code: "unauthenticated"}},
    );
    for (const [token, status, code] of [
      ["invalid", 401, "unauthenticated"],
      ["unavailable", 503, "organization_shareable_join_unavailable"],
      ["unknown", 503, "organization_shareable_join_unavailable"],
    ] as const) {
      assertResponse(
        await rawRequest(
          address.port,
          method,
          path,
          {authorization: `Bearer ${token}`},
          "not-json",
        ),
        status,
        {error: {code}},
      );
    }
    assertResponse(
      await rawRequest(
        address.port,
        method,
        path,
        {authorization: "Bearer valid"},
        "not-json",
      ),
      400,
      {error: {code: "invalid_organization_shareable_join_request"}},
    );
  }
  assert.equal(verifierCalls, 8);
  assert.equal(storeCalls, 0);
});

test("preview rejects query or declared body without reading it", async () => {
  let previewCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({verify: async () => identity}),
    organizationShareableJoinLinkStore: {
      create: async () => assert.fail("preview must not create"),
      preview: async () => {
        previewCalls += 1;
        return previewResult;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [path, headers, body, autoContentLength] of [
    [`${previewPath()}?`, {authorization: "Bearer token"}, "", false],
    [
      `${previewPath()}?private=value`,
      {authorization: "Bearer token"},
      "",
      false,
    ],
    [
      previewPath(),
      {authorization: "Bearer token", "content-length": "1"},
      "x",
      true,
    ],
    [
      previewPath(),
      {authorization: "Bearer token", "transfer-encoding": "chunked"},
      "not-json",
      true,
    ],
  ] as const) {
    assertResponse(
      await rawRequest(
        address.port,
        "GET",
        path,
        headers,
        body,
        autoContentLength,
      ),
      400,
      {error: {code: "invalid_organization_shareable_join_request"}},
    );
  }
  assert.equal(previewCalls, 0);
});

test("create reuses the shared JSON and inclusive 1 MiB boundary", async () => {
  let createCalls = 0;
  const server = createBackendServer({
    ...baseDependencies({verify: async () => identity}),
    organizationShareableJoinLinkStore: {
      create: async () => {
        createCalls += 1;
        return createResult;
      },
      preview: async () => previewResult,
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const body of ["", "not-json"]) {
    assertResponse(
      await rawRequest(
        address.port,
        "POST",
        createPath(),
        {authorization: "Bearer token"},
        body,
      ),
      400,
      {error: {code: "invalid_json"}},
    );
  }
  for (const body of [
    "{}",
    "[]",
    JSON.stringify({link_id: "not-a-uuid"}),
    JSON.stringify({link_id: linkId, actor_app_user_id: workspaceId}),
  ]) {
    assertResponse(
      await rawRequest(
        address.port,
        "POST",
        createPath(),
        {authorization: "Bearer token"},
        body,
      ),
      400,
      {error: {code: "invalid_organization_shareable_join_request"}},
    );
  }

  const validBody = JSON.stringify({link_id: linkId});
  const oneMiBBody = validBody + " ".repeat(
    1024 * 1024 - Buffer.byteLength(validBody),
  );
  assertResponse(
    await rawRequest(
      address.port,
      "POST",
      createPath(),
      {authorization: "Bearer token", "transfer-encoding": "chunked"},
      oneMiBBody,
    ),
    200,
    createWire(),
  );
  assertResponse(
    await rawRequest(
      address.port,
      "POST",
      createPath(),
      {authorization: "Bearer token", "transfer-encoding": "chunked"},
      `${oneMiBBody} `,
    ),
    413,
    {error: {code: "payload_too_large"}},
  );
  assert.equal(createCalls, 1);
});

test("routes expose only stable dependency and store errors", async () => {
  const missingStore = createBackendServer(
    baseDependencies({verify: async () => identity}),
  );
  const missingStoreAddress = await listen(missingStore);
  test.after(() => close(missingStore));
  assertResponse(
    await rawRequest(
      missingStoreAddress.port,
      "POST",
      createPath(),
      {authorization: "Bearer token"},
      "not-json",
    ),
    503,
    {error: {code: "organization_shareable_join_unavailable"}},
  );

  const typedCases = [
    ["123e4567-e89b-12d3-a456-426614174010", 400,
      "invalid_organization_shareable_join_request"],
    ["123e4567-e89b-12d3-a456-426614174011", 403,
      "organization_shareable_join_forbidden"],
    ["123e4567-e89b-12d3-a456-426614174012", 409,
      "organization_shareable_join_conflict"],
    ["123e4567-e89b-12d3-a456-426614174013", 503,
      "organization_shareable_join_unavailable"],
  ] as const;
  const unknownId = "123e4567-e89b-12d3-a456-426614174014";
  const sensitive = "database SQL and identity secret";
  const server = createBackendServer({
    ...baseDependencies({verify: async () => identity}),
    organizationShareableJoinLinkStore: {
      create: async (_actor, selectedId) => {
        const entry = typedCases.find(([id]) => id === selectedId);
        if (entry !== undefined) {
          throw new OrganizationShareableJoinLinkStoreError(entry[2]);
        }
        throw new Error(sensitive);
      },
      preview: async (_actor, selectedId) => {
        const entry = typedCases.find(([id]) => id === selectedId);
        if (entry !== undefined) {
          throw new OrganizationShareableJoinLinkStoreError(entry[2]);
        }
        throw new Error(sensitive);
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [id, status, code] of typedCases) {
    assertResponse(
      await rawRequest(
        address.port,
        "POST",
        createPath(),
        {authorization: "Bearer token"},
        JSON.stringify({link_id: id}),
      ),
      status,
      {error: {code}},
    );
    assertResponse(
      await rawRequest(
        address.port,
        "GET",
        previewPath(id),
        {authorization: "Bearer token"},
        "",
        false,
      ),
      status,
      {error: {code}},
    );
  }
  for (const [method, path, body] of [
    ["POST", createPath(), JSON.stringify({link_id: unknownId})],
    ["GET", previewPath(unknownId), ""],
  ] as const) {
    const response = await rawRequest(
      address.port,
      method,
      path,
      {authorization: "Bearer token"},
      body,
      method === "POST",
    );
    assertResponse(response, 503, {
      error: {code: "organization_shareable_join_unavailable"},
    });
    assert.equal(JSON.stringify(response.body).includes(sensitive), false);
  }
});

test("both routes wait for their store promise before responding", async () => {
  for (const operation of ["create", "preview"] as const) {
    let release: (() => void) | undefined;
    let started: (() => void) | undefined;
    const storeStarted = new Promise<void>((resolve) => { started = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const server = createBackendServer({
      ...baseDependencies({verify: async () => identity}),
      organizationShareableJoinLinkStore: {
        create: async () => {
          if (operation === "create") {
            started?.();
            await gate;
          }
          return createResult;
        },
        preview: async () => {
          if (operation === "preview") {
            started?.();
            await gate;
          }
          return previewResult;
        },
      },
    });
    const address = await listen(server);
    let responseSettled = false;
    const responsePromise = rawRequest(
      address.port,
      operation === "create" ? "POST" : "GET",
      operation === "create" ? createPath() : previewPath(),
      {authorization: "Bearer token"},
      operation === "create" ? JSON.stringify({link_id: linkId}) : "",
      operation === "create",
    ).then((response) => {
      responseSettled = true;
      return response;
    });
    await storeStarted;
    assert.equal(responseSettled, false);
    release?.();
    assertResponse(
      await responsePromise,
      200,
      operation === "create" ? createWire() : previewWire(),
    );
    await close(server);
  }
});

function createPath(value = workspaceId): string {
  return `/v1/organizations/${value}/shareable-join-links`;
}

function previewPath(value = linkId): string {
  return `/v1/organization-shareable-join-links/${value}`;
}

function createWire(): Readonly<Record<string, unknown>> {
  return {
    organization_shareable_join_link_contract_id:
      "organization-shareable-join-link:v1",
    link_id: linkId,
    organization_workspace_id: workspaceId,
    issued_at_utc: createResult.issuedAtUtc,
    expires_at_utc: createResult.expiresAtUtc,
  };
}

function previewWire(): Readonly<Record<string, unknown>> {
  return {
    organization_shareable_join_link_preview_contract_id:
      "organization-shareable-join-link-preview:v1",
    link_id: linkId,
    organization_name: previewResult.organizationName,
    expires_at_utc: previewResult.expiresAtUtc,
  };
}

function baseDependencies(identityVerifier: {
  verify(token: string): Promise<VerifiedIdentity>;
}) {
  return {
    identityVerifier,
    contextStore: {
      loadOrCreate: async () => {
        throw new Error("SessionContext must not run for shareable link tests");
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
  autoContentLength = true,
): Promise<RawResponse> {
  return new Promise((resolve, reject) => {
    const requestHeaders = {...headers};
    if (
      autoContentLength &&
      requestHeaders["transfer-encoding"] === undefined &&
      requestHeaders["content-length"] === undefined
    ) {
      requestHeaders["content-length"] = String(Buffer.byteLength(body));
    }
    const request = httpRequest(
      {host: "127.0.0.1", port, method, path, headers: requestHeaders},
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk: Buffer) => chunks.push(chunk));
        response.on("end", () => {
          try {
            const text = Buffer.concat(chunks).toString("utf8");
            resolve({
              status: response.statusCode ?? 0,
              headers: response.headers,
              body: text.length === 0 ? undefined : JSON.parse(text) as unknown,
            });
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    request.on("error", reject);
    if (!autoContentLength && body.length === 0) {
      request.end();
    } else {
      request.end(body);
    }
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
