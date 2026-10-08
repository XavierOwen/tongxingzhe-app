import assert from "node:assert/strict";
import {request as httpRequest} from "node:http";
import type {AddressInfo} from "node:net";
import test from "node:test";

import type {VerifiedIdentity} from "../src/identity.js";
import type {
  PersonalTargetCsvImportConfirmInput,
  PersonalTargetCsvImportConfirmReceipt,
  PersonalTargetCsvImportPreviewReceipt,
  PersonalTargetCsvImportStore,
} from "../src/personal-target-csv-import.js";
import {createBackendServer} from "../src/server.js";
import type {SessionContext} from "../src/session-context.js";

const identity: VerifiedIdentity = {
  issuer: "https://csv-import-http.example.test/auth/v1",
  subject: "csv-import-http-owner",
};
const context: SessionContext = {
  appUserId: "11111111-1111-4111-8111-111111111111",
  current: {
    workspace: {
      id: "22222222-2222-4222-8222-222222222222",
      kind: "personal",
      name: "个人空间",
    },
    project: {
      id: "33333333-3333-4333-8333-333333333333",
      name: "校园推广",
    },
    questionnaireVersion: {
      id: "44444444-4444-4444-8444-444444444444",
      versionNumber: 1,
    },
  },
  capabilities: ["import_target_pii"],
};
const rows = [
  {
    target_type: "person" as const,
    display_name: "王小明",
    phone: "123456",
    email: null,
  },
  {
    target_type: "institution" as const,
    display_name: "北河学校",
    phone: null,
    email: "office@example.test",
  },
];
const previewReceipt: PersonalTargetCsvImportPreviewReceipt = {
  contract_id: "personal-target-csv-import-preview:v1",
  preview_id: "55555555-5555-4555-8555-555555555555",
  row_count: 2,
  hinted_rows: [2],
  previewed_at_utc: "2030-01-01T00:00:00.000Z",
  expires_at_utc: "2030-01-01T00:15:00.000Z",
};
const requestId = "66666666-6666-4666-8666-666666666666";
const confirmInput: PersonalTargetCsvImportConfirmInput = {
  previewId: previewReceipt.preview_id,
  requestId,
  rows,
  actions: ["create", "skip"],
};

test("CSV import preview returns a no-store normalized preview bound to trusted scope", async () => {
  let previewArgs: Parameters<PersonalTargetCsvImportStore["preview"]> | undefined;
  const server = createBackendServer({
    ...dependencies(),
    personalTargetCsvImportStore: {
      preview: async (...args) => {
        previewArgs = args;
        return previewReceipt;
      },
      confirm: async () => assert.fail("preview must not confirm"),
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  const response = await rawRequest(
    address.port,
    "POST",
    "/v1/promotion-targets/imports/csv/preview",
    {authorization: "Bearer token", "content-type": "text/csv; charset=utf-8"},
    "target_type,display_name,phone,email\r\nperson, 王小明 , 123456 ,\r\ninstitution,北河学校,, office@example.test \r\n",
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers["cache-control"], "no-store");
  assert.deepEqual(previewArgs, [identity, context.current.project.id, rows]);
  assert.deepEqual(response.body, {
    receipt: previewReceipt,
    rows: [
      {row_number: 1, ...rows[0], hinted: false},
      {row_number: 2, ...rows[1], hinted: true},
    ],
  });
});

test("CSV import confirm returns 200 for confirmation and 409 for stale preview", async () => {
  const receipts: PersonalTargetCsvImportConfirmReceipt[] = [
    {
      contract_id: "personal-target-csv-import-confirm:v1",
      preview_id: confirmInput.previewId,
      request_id: requestId,
      outcome: "confirmed",
      row_count: 2,
      hint_count: 1,
      created_count: 1,
      created_targets: [{
        row_number: 1,
        target_id: "77777777-7777-4777-8777-777777777777",
      }],
      completed_at_utc: "2030-01-01T00:01:00.000Z",
    },
    {
      contract_id: "personal-target-csv-import-confirm:v1",
      preview_id: confirmInput.previewId,
      request_id: requestId,
      outcome: "stale_preview",
      row_count: 2,
      hint_count: 1,
      created_count: 0,
      created_targets: [],
      completed_at_utc: "2030-01-01T00:02:00.000Z",
    },
  ];
  const received: Parameters<PersonalTargetCsvImportStore["confirm"]>[] = [];
  const server = createBackendServer({
    ...dependencies(),
    personalTargetCsvImportStore: {
      preview: async () => assert.fail("confirm must not preview"),
      confirm: async (...args) => {
        received.push(args);
        return receipts[received.length - 1] as PersonalTargetCsvImportConfirmReceipt;
      },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [index, expectedStatus] of [200, 409].entries()) {
    const response = await rawRequest(
      address.port,
      "POST",
      "/v1/promotion-targets/imports/csv/confirm",
      {authorization: "Bearer token", "content-type": "application/json"},
      JSON.stringify({
        preview_id: confirmInput.previewId,
        request_id: confirmInput.requestId,
        rows,
        actions: confirmInput.actions,
      }),
    );
    assert.equal(response.status, expectedStatus);
    assert.equal(response.headers["cache-control"], "no-store");
    assert.deepEqual(response.body, {receipt: receipts[index]});
  }
  assert.deepEqual(received, [
    [identity, context.current.project.id, confirmInput],
    [identity, context.current.project.id, confirmInput],
  ]);
});

test("CSV import authenticates and checks capability before consuming invalid or oversized bodies", async () => {
  let storeCalls = 0;
  const cases = [
    {authorization: undefined, capabilities: context.capabilities, body: "x".repeat(1024 * 1024 + 1), expected: 401},
    {authorization: "Bearer token", capabilities: [], body: "not csv", expected: 403},
  ] as const;
  for (const item of cases) {
    const server = createBackendServer({
      ...dependencies({capabilities: item.capabilities}),
      personalTargetCsvImportStore: {
        preview: async () => { storeCalls++; throw new Error("must not preview"); },
        confirm: async () => { storeCalls++; throw new Error("must not confirm"); },
      },
    });
    const address = await listen(server);
    test.after(() => close(server));
    const response = await rawRequest(
      address.port,
      "POST",
      "/v1/promotion-targets/imports/csv/preview",
      {
        ...(item.authorization === undefined ? {} : {authorization: item.authorization}),
        "content-type": "text/csv",
      },
      item.body,
    );
    assert.equal(response.status, item.expected);
    assert.equal(storeCalls, 0);
  }
});

test("CSV import rejects bad request shape, media type, CSV, and confirm JSON", async () => {
  const server = createBackendServer({
    ...dependencies(),
    personalTargetCsvImportStore: {
      preview: async () => assert.fail("invalid preview must not reach the store"),
      confirm: async () => assert.fail("invalid confirm must not reach the store"),
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const auth = {authorization: "Bearer token"};
  const previewPath = "/v1/promotion-targets/imports/csv/preview";
  const confirmPath = "/v1/promotion-targets/imports/csv/confirm";
  const previewCases = [
    {path: previewPath, contentType: "text/csv", body: "", status: 400},
    {path: `${previewPath}?`, contentType: "text/csv", body: "x", status: 400},
    {path: `${previewPath}?unexpected=1`, contentType: "text/csv", body: "x", status: 400},
    {path: previewPath, contentType: "application/json", body: "{}", status: 415},
    {path: previewPath, contentType: "text/csv", body: "\n", status: 422},
    {path: previewPath, contentType: "text/csv", body: Buffer.from([0xff]), status: 422},
    {path: previewPath, contentType: "text/csv", body: "wrong,header\na,b", status: 422},
    {path: previewPath, contentType: "text/csv", body: "target_type,display_name,phone,email\nperson,name,phone", status: 422},
    {path: previewPath, contentType: "text/csv", body: "target_type,display_name,phone,email\n\"broken,name,,,", status: 422},
  ] as const;
  for (const item of previewCases) {
    const response = await rawRequest(
      address.port,
      "POST",
      item.path,
      {...auth, "content-type": item.contentType},
      item.body,
    );
    assert.equal(response.status, item.status, item.path);
  }

  for (const body of ["{", JSON.stringify({preview_id: confirmInput.previewId, request_id: requestId, rows, actions: confirmInput.actions, extra: true})]) {
    const response = await rawRequest(
      address.port,
      "POST",
      confirmPath,
      {...auth, "content-type": "application/json"},
      body,
    );
    assert.equal(response.status, 400);
  }
  const emptyConfirm = await rawRequest(
    address.port,
    "POST",
    confirmPath,
    {...auth, "content-type": "application/json"},
    "",
  );
  assert.equal(emptyConfirm.status, 400);
  for (const item of [
    {path: `${confirmPath}?`, contentType: "application/json", status: 400},
    {path: `${confirmPath}?unexpected=1`, contentType: "application/json", status: 400},
    {path: confirmPath, contentType: "text/csv", status: 415},
  ]) {
    const response = await rawRequest(
      address.port,
      "POST",
      item.path,
      {...auth, "content-type": item.contentType},
      JSON.stringify({
        preview_id: confirmInput.previewId,
        request_id: requestId,
        rows,
        actions: confirmInput.actions,
      }),
    );
    assert.equal(response.status, item.status);
  }
});

test("CSV import returns 413 above one MiB and hides unknown store failures", async () => {
  let oversizedStoreCalls = 0;
  const oversizedServer = createBackendServer({
    ...dependencies(),
    personalTargetCsvImportStore: {
      preview: async () => { oversizedStoreCalls++; throw new Error("must not preview"); },
      confirm: async () => assert.fail("oversized body must not confirm"),
    },
  });
  const oversizedAddress = await listen(oversizedServer);
  test.after(() => close(oversizedServer));
  const oversized = await rawRequest(
    oversizedAddress.port,
    "POST",
    "/v1/promotion-targets/imports/csv/preview",
    {authorization: "Bearer token", "content-type": "text/csv"},
    `target_type,display_name,phone,email\n${"a".repeat(1024 * 1024)}`,
  );
  assert.equal(oversized.status, 413);
  const oversizedConfirm = await rawRequest(
    oversizedAddress.port,
    "POST",
    "/v1/promotion-targets/imports/csv/confirm",
    {authorization: "Bearer token", "content-type": "application/json"},
    "x".repeat(1024 * 1024 + 1),
  );
  assert.equal(oversizedConfirm.status, 413);
  assert.equal(oversizedStoreCalls, 0);

  const failure = new Error("synthetic PII: waybill@example.test; raw database password");
  const server = createBackendServer({
    ...dependencies(),
    personalTargetCsvImportStore: {
      preview: async () => { throw failure; },
      confirm: async () => assert.fail("preview failure test must not confirm"),
    },
  });
  const address = await listen(server);
  test.after(() => close(server));
  const response = await rawRequest(
    address.port,
    "POST",
    "/v1/promotion-targets/imports/csv/preview",
    {authorization: "Bearer token", "content-type": "text/csv"},
    "target_type,display_name,phone,email\nperson,Example,,",
  );
  assert.equal(response.status, 503);
  assert.doesNotMatch(JSON.stringify(response.body), /waybill@example\.test|database password|synthetic PII/);
});

test("wrong methods return 404 without authentication or store access", async () => {
  let verifierCalls = 0;
  let storeCalls = 0;
  const server = createBackendServer({
    ...dependencies({verify: async () => { verifierCalls++; return identity; }}),
    personalTargetCsvImportStore: {
      preview: async () => { storeCalls++; return previewReceipt; },
      confirm: async () => { storeCalls++; throw new Error("must not confirm"); },
    },
  });
  const address = await listen(server);
  test.after(() => close(server));

  for (const [method, path] of [
    ["GET", "/v1/promotion-targets/imports/csv/preview"],
    ["PUT", "/v1/promotion-targets/imports/csv/confirm"],
  ] as const) {
    const response = await rawRequest(address.port, method, path, {}, "");
    assert.equal(response.status, 404);
  }
  assert.equal(verifierCalls, 0);
  assert.equal(storeCalls, 0);
});

function dependencies(overrides: {
  verify?: () => Promise<VerifiedIdentity>;
  capabilities?: readonly string[];
} = {}) {
  return {
    identityVerifier: {
      verify: overrides.verify ?? (async () => identity),
    },
    contextStore: {
      loadOrCreate: async () => ({
        ...context,
        capabilities: overrides.capabilities ?? context.capabilities,
      }),
    },
  };
}

async function listen(server: ReturnType<typeof createBackendServer>): Promise<AddressInfo> {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return server.address() as AddressInfo;
}

function close(server: ReturnType<typeof createBackendServer>): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}

function rawRequest(
  port: number,
  method: string,
  path: string,
  headers: Record<string, string>,
  body: string | Buffer,
): Promise<{status: number; headers: Record<string, string | string[] | undefined>; body: unknown}> {
  const bytes = Buffer.isBuffer(body) ? body : Buffer.from(body);
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      {
        host: "127.0.0.1",
        port,
        path,
        method,
        headers: {...headers, "content-length": bytes.length},
      },
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        response.on("end", () => resolve({
          status: response.statusCode ?? 0,
          headers: response.headers,
          body: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown,
        }));
      },
    );
    request.on("error", reject);
    request.end(bytes);
  });
}
