import assert from "node:assert/strict";
import test from "node:test";

import {IdentityVerificationError, type VerifiedIdentity} from "../src/identity.js";
import {
  handlePersonalTargetCsvImportConfirm,
  handlePersonalTargetCsvImportPreview,
  parsePersonalTargetCsv,
  PersonalTargetCsvImportStoreError,
  PostgresPersonalTargetCsvImportStore,
  type PersonalTargetCsvImportConfirmInput,
  type PersonalTargetCsvImportConfirmReceipt,
  type PersonalTargetCsvImportPreviewReceipt,
} from "../src/personal-target-csv-import.js";
import type {SessionContext} from "../src/session-context.js";

const identity: VerifiedIdentity = {
  issuer: "https://csv-import.example.test/auth/v1",
  subject: "csv-import-user",
};
const projectId = "33333333-3333-4333-8333-333333333333";
const previewId = "55555555-5555-4555-8555-555555555555";
const requestId = "66666666-6666-4666-8666-666666666666";
const targetId = "77777777-7777-4777-8777-777777777777";
const context: SessionContext = {
  appUserId: "11111111-1111-4111-8111-111111111111",
  current: {
    workspace: {id: "22222222-2222-4222-8222-222222222222", kind: "personal", name: "Personal"},
    project: {id: projectId, name: "Project"},
    questionnaireVersion: {id: "44444444-4444-4444-8444-444444444444", versionNumber: 1},
  },
  capabilities: ["import_target_pii"],
};
const csv = Buffer.from("target_type,display_name,phone,email\r\nperson, Alice , 123 , a@example.test\r\ninstitution,\"School, Inc.\",,\"\"\"admin\"\"@school.test\"\r\n", "utf8");
const rows = [
  {target_type: "person" as const, display_name: "Alice", phone: "123", email: "a@example.test"},
  {target_type: "institution" as const, display_name: "School, Inc.", phone: null, email: '"admin"@school.test'},
];
const previewReceipt: PersonalTargetCsvImportPreviewReceipt = {
  contract_id: "personal-target-csv-import-preview:v1",
  preview_id: previewId,
  row_count: 2,
  hinted_rows: [2],
  previewed_at_utc: "2030-01-01T00:00:00.123456Z",
  expires_at_utc: "2030-01-01T00:15:00.123456Z",
};
const confirmReceipt: PersonalTargetCsvImportConfirmReceipt = {
  contract_id: "personal-target-csv-import-confirm:v1",
  preview_id: previewId,
  request_id: requestId,
  outcome: "confirmed",
  row_count: 2,
  hint_count: 1,
  created_count: 2,
  created_targets: [{row_number: 1, target_id: targetId}, {row_number: 2, target_id: "88888888-8888-4888-8888-888888888888"}],
  completed_at_utc: "2030-01-01T00:00:01.123456Z",
};

test("CSV parser accepts RFC4180 quoting, BOM, LF, CRLF, and quoted newlines", () => {
  const parsed = parsePersonalTargetCsv(Buffer.from(`\ufefftarget_type,display_name,phone,email\n` +
    `person,\"Alice, A\",,alice@example.test\n` +
    `institution,\"School\r\nNorth\",  ,\"\"\"admin\"\"@school.test\"\n`));
  assert.deepEqual(parsed, {
    rows: [
      {target_type: "person", display_name: "Alice, A", phone: null, email: "alice@example.test"},
      {target_type: "institution", display_name: "School\r\nNorth", phone: null, email: '"admin"@school.test'},
    ],
    issues: [],
  });
  assert.deepEqual(parsePersonalTargetCsv(Buffer.from("target_type,display_name,phone,email\r\n")), {rows: [], issues: []});
});

test("CSV parser rejects malformed quotes, bare CR, invalid UTF-8, and bad headers", () => {
  for (const source of [
    "target_type,display_name,phone,email\nperson,\"bad,x,y,z\n",
    "target_type,display_name,phone,email\nperson,bad\rdata,,\n",
    "Target_type,display_name,phone,email\n",
  ]) {
    assert.notDeepEqual(parsePersonalTargetCsv(Buffer.from(source)).issues, []);
  }
  assert.equal(parsePersonalTargetCsv(Buffer.from([0xc3, 0x28])).issues[0]?.code, "invalid_utf8");
});

test("CSV row validation is value-free, code-point bounded, and caps at 500", () => {
  const invalid = parsePersonalTargetCsv(Buffer.from(
    "target_type,display_name,phone,email\n" +
    `PERSON,\"Secret Name\",${"p".repeat(81)},${"e".repeat(321)}\n` +
    `person,${"😀".repeat(201)},,\n`));
  assert.deepEqual(invalid.issues, [
    {row_number: 1, field: "target_type", code: "invalid_value"},
    {row_number: 1, field: "phone", code: "invalid_length"},
    {row_number: 1, field: "email", code: "invalid_length"},
    {row_number: 2, field: "display_name", code: "invalid_length"},
  ]);
  assert.doesNotMatch(JSON.stringify(invalid), /Secret|pppp|eeee/);
  const boundary = parsePersonalTargetCsv(Buffer.from(
    "target_type,display_name,phone,email\n" +
    `person,${"😀".repeat(200)},${"p".repeat(80)},${"e".repeat(320)}\n`));
  assert.equal(boundary.rows.length, 1);
  assert.deepEqual(boundary.issues, []);
  assert.equal(parsePersonalTargetCsv(Buffer.from("target_type,display_name,phone,email\n" + "person,A,,\n".repeat(500))).rows.length, 500);
  assert.deepEqual(parsePersonalTargetCsv(Buffer.from("target_type,display_name,phone,email\n" + "person,A,,\n".repeat(501))).issues[0], {row_number: 501, field: "row", code: "too_many_rows"});
});

test("preview and confirm use trusted scope and return value-free failures", async () => {
  const events: string[] = [];
  const deps = dependencies({
    verify: async () => {events.push("verify"); return identity;},
    loadContext: async () => {events.push("context"); return context;},
    preview: async (_identity, project, input) => {events.push("preview"); assert.equal(project, projectId); assert.deepEqual(input, rows); return previewReceipt;},
    confirm: async (_identity, project, input) => {events.push("confirm"); assert.equal(project, projectId); assert.deepEqual(input, confirmInput); return confirmReceipt;},
  });
  const preview = await handlePersonalTargetCsvImportPreview(request(csv), deps);
  assert.equal(preview.status, 200);
  assert.deepEqual(events, ["verify", "context", "preview"]);
  assert.deepEqual(preview.body, {receipt: previewReceipt, rows: [
    {row_number: 1, ...rows[0], hinted: false},
    {row_number: 2, ...rows[1], hinted: true},
  ]});

  events.length = 0;
  const confirmed = await handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from(JSON.stringify(confirmBody))), deps);
  assert.deepEqual(confirmed, {status: 200, body: {receipt: confirmReceipt}});
  assert.deepEqual(events, ["verify", "context", "confirm"]);
  assert.doesNotMatch(JSON.stringify(confirmed), /actor|issuer|subject|Secret|SQL/);

  const stale = await handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from(JSON.stringify(confirmBody))), dependencies({confirm: async () => ({...confirmReceipt, outcome: "stale_preview", created_count: 0, created_targets: []})}));
  assert.equal(stale.status, 409);
  assert.deepEqual(Object.keys(stale.body), ["receipt"]);
});

test("authentication, workspace, capability, shape, media, and missing store gate body reads", async () => {
  let bodyReads = 0;
  let contextReads = 0;
  let storeCalls = 0;
  const makeRequest = (overrides: Partial<Parameters<typeof handlePersonalTargetCsvImportPreview>[0]> = {}) => request(csv, {readBody: async () => {bodyReads++; return csv;}, ...overrides});
  const base = dependencies({
    loadContext: async () => {contextReads++; return context;},
    preview: async () => {storeCalls++; return previewReceipt;},
  });
  for (const result of [
    await handlePersonalTargetCsvImportPreview(makeRequest({authorization: undefined}), base),
    await handlePersonalTargetCsvImportPreview(makeRequest({hasQuery: true}), base),
    await handlePersonalTargetCsvImportPreview(makeRequest({hasBody: false}), base),
    await handlePersonalTargetCsvImportPreview(makeRequest({contentType: "application/json"}), base),
    await handlePersonalTargetCsvImportPreview(makeRequest(), dependencies({loadContext: async () => ({...context, current: {...context.current, workspace: {...context.current.workspace, kind: "organization"}}})})),
    await handlePersonalTargetCsvImportPreview(makeRequest(), dependencies({loadContext: async () => ({...context, capabilities: []})})),
    await handlePersonalTargetCsvImportPreview(makeRequest(), dependencies({store: undefined})),
  ]) assert.notEqual(result.status, 200, `unexpected success: ${JSON.stringify(result)}`);
  assert.equal(bodyReads, 0);
  assert.equal(storeCalls, 0);

  const contextsBeforeInvalidToken = contextReads;
  const invalidToken = await handlePersonalTargetCsvImportPreview(makeRequest(), dependencies({verify: async () => {throw new IdentityVerificationError();}}));
  assert.equal(invalidToken.status, 401);
  assert.equal(bodyReads, 0);
  assert.equal(contextReads, contextsBeforeInvalidToken);
});

test("HTTP failures use stable status codes and preserve reader errors", async () => {
  const invalidCsv = await handlePersonalTargetCsvImportPreview(request(Buffer.from("bad")), dependencies());
  assert.deepEqual(invalidCsv, {status: 422, body: {error: {code: "invalid_personal_target_csv_import_rows", issues: [{row_number: 1, field: "header", code: "invalid_header"}]}}});
  const invalidUtf8 = await handlePersonalTargetCsvImportPreview(request(Buffer.from([0xc3, 0x28])), dependencies());
  assert.equal(invalidUtf8.status, 422);
  assert.equal((invalidUtf8.body.error as {code: string}).code, "invalid_personal_target_csv_import_rows");
  const csvMedia = await handlePersonalTargetCsvImportPreview(request(csv, {contentType: "application/json"}), dependencies());
  const jsonMedia = await handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from("{}")), dependencies({confirm: async () => confirmReceipt}));
  assert.deepEqual(csvMedia, {status: 415, body: {error: {code: "unsupported_personal_target_csv_import_media_type"}}});
  assert.deepEqual(jsonMedia, {status: 400, body: {error: {code: "invalid_personal_target_csv_import_request"}}});

  const bodyTooLarge = Object.assign(new Error("request body too large"), {status: 413});
  await assert.rejects(() => handlePersonalTargetCsvImportPreview(request(csv, {readBody: async () => {throw bodyTooLarge;}}), dependencies()), (error: unknown) => error === bodyTooLarge);
  await assert.rejects(() => handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from("{}"), {readBody: async () => {throw bodyTooLarge;}}), dependencies()), (error: unknown) => error === bodyTooLarge);
  for (const [storeError, operation, status, code] of [
    [new PersonalTargetCsvImportStoreError("forbidden"), "preview", 403, "personal_target_csv_import_forbidden"],
    [new PersonalTargetCsvImportStoreError("invalid_rows"), "preview", 422, "invalid_personal_target_csv_import_rows"],
    [new PersonalTargetCsvImportStoreError("invalid_rows"), "confirm", 400, "invalid_personal_target_csv_import_request"],
    [new PersonalTargetCsvImportStoreError("invalid_confirmation"), "confirm", 400, "invalid_personal_target_csv_import_request"],
    [new PersonalTargetCsvImportStoreError("conflict"), "confirm", 409, "personal_target_csv_import_conflict"],
    [new Error("private DB details"), "preview", 503, "personal_target_csv_import_unavailable"],
  ] as const) {
    const result = operation === "preview"
      ? await handlePersonalTargetCsvImportPreview(request(csv), dependencies({preview: async () => {throw storeError;}}))
      : await handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from(JSON.stringify(confirmBody))), dependencies({confirm: async () => {throw storeError;}}));
    assert.equal(result.status, status);
    assert.deepEqual(result.body, {error: {code}});
    assert.doesNotMatch(JSON.stringify(result), /private DB details/);
  }
});

test("confirm JSON requires exact keys, canonical UUIDs, normalized row values, and matching actions", async () => {
  let storeCalls = 0;
  const deps = dependencies({confirm: async () => {storeCalls++; return confirmReceipt;}});
  for (const [index, body] of [
    {...confirmBody, extra: true},
    {...confirmBody, preview_id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"},
    {...confirmBody, actions: ["skip"]},
    {...confirmBody, rows: [{...confirmBody.rows[0], actor_id: "secret"}, confirmBody.rows[1]]},
    {...confirmBody, rows: [{...confirmBody.rows[0], display_name: "  "}, confirmBody.rows[1]]},
    {...confirmBody, actions: ["delete", "create"]},
  ].entries()) {
    const result = await handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from(JSON.stringify(body))), deps);
    assert.equal(result.status, 400, `invalid fixture ${index}: ${JSON.stringify(result)}`);
  }
  assert.equal(storeCalls, 0);
  let received: PersonalTargetCsvImportConfirmInput | undefined;
  const normalizedBody = {...confirmBody, rows: [{...rows[0], display_name: " Alice ", phone: "   "}, rows[1]]};
  const result = await handlePersonalTargetCsvImportConfirm(confirmRequest(Buffer.from(JSON.stringify(normalizedBody))), dependencies({confirm: async (_identity, _project, input) => {received = input; return confirmReceipt;}}));
  assert.equal(result.status, 200);
  assert.deepEqual(received?.rows[0], {...rows[0], phone: null});
});

test("database adapter calls only the two bridges with exact parameter order", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresPersonalTargetCsvImportStore(async (text, values) => {
    calls.push({text, values});
    return {rows: [calls.length === 1 ? dbPreview : dbConfirm]};
  });
  assert.deepEqual(await store.preview(identity, projectId, rows), previewReceipt);
  assert.deepEqual(await store.confirm(identity, projectId, confirmInput), confirmReceipt);
  assert.match(calls[0]?.text ?? "", /app_data\.preview_personal_target_csv_import_v1\(\s*\$1::text,\s*\$2::text,\s*\$3::uuid,\s*\$4::jsonb/s);
  assert.match(calls[1]?.text ?? "", /app_data\.confirm_personal_target_csv_import_v1\(\s*\$1::text,\s*\$2::text,\s*\$3::uuid,\s*\$4::uuid,\s*\$5::uuid,\s*\$6::jsonb,\s*\$7::jsonb/s);
  assert.deepEqual(calls[0]?.values, [identity.issuer, identity.subject, projectId, JSON.stringify(rows)]);
  assert.deepEqual(calls[1]?.values, [identity.issuer, identity.subject, projectId, previewId, requestId, JSON.stringify(rows), JSON.stringify(["create", "create"])]);
  assert.doesNotMatch(calls[0]?.text ?? "", /app_private|BEGIN|COMMIT/i);
});

test("adapter enforces strict receipts, expected IDs and counts, and one result row", async () => {
  for (const dbValue of [
    {...dbPreview, extra: true},
    {...dbPreview, contract_id: "wrong"},
    {...dbPreview, preview_id: "not-uuid"},
    {...dbPreview, row_count: 1},
    {...dbPreview, hinted_rows: [2, 1]},
    {...dbPreview, hinted_rows: [3]},
    {...dbPreview, previewed_at_utc: "bad"},
  ]) await assert.rejects(() => new PostgresPersonalTargetCsvImportStore(async () => ({rows: [dbValue]})).preview(identity, projectId, rows), invalidStoreError);

  for (const dbValue of [
    {...dbConfirm, extra: true},
    {...dbConfirm, request_id: "88888888-8888-4888-8888-888888888888"},
    {...dbConfirm, row_count: 3},
    {...dbConfirm, hint_count: 3},
    {...dbConfirm, created_count: 1},
    {...dbConfirm, created_targets: [{row_number: 3, target_id: targetId}, {row_number: 1, target_id: targetId}]},
    {...dbConfirm, created_targets: [{row_number: 1, target_id: targetId}, {row_number: 2, target_id: targetId}]},
    {...dbConfirm, created_targets: [{row_number: 1, target_id: "bad"}, dbConfirm.created_targets[1]]},
  ]) await assert.rejects(() => new PostgresPersonalTargetCsvImportStore(async () => ({rows: [dbValue]})).confirm(identity, projectId, confirmInput), invalidStoreError);

  for (const resultRows of [[], [dbPreview, dbPreview]]) {
    await assert.rejects(() => new PostgresPersonalTargetCsvImportStore(async () => ({rows: resultRows})).preview(identity, projectId, []), invalidStoreError);
  }
});

test("database SQLSTATE and fixed message allowlist maps to stable safe failures", async () => {
  for (const [code, message, expected] of [
    ["42501", "personal target CSV import scope is forbidden", "forbidden"],
    ["22023", "invalid personal target CSV import rows", "invalid_rows"],
    ["23505", "personal target CSV import request conflict", "conflict"],
  ] as const) {
    await assert.rejects(() => new PostgresPersonalTargetCsvImportStore(async () => {throw Object.assign(new Error(message), {code});}).preview(identity, projectId, rows), (error: unknown) => error instanceof PersonalTargetCsvImportStoreError && error.code === expected && !error.message.includes(message));
  }
  for (const message of ["invalid personal target CSV import actions", "invalid personal target CSV import request", "invalid personal target CSV import confirmation"]) {
    await assert.rejects(() => new PostgresPersonalTargetCsvImportStore(async () => {throw Object.assign(new Error(message), {code: "22023"});}).confirm(identity, projectId, confirmInput), (error: unknown) => error instanceof PersonalTargetCsvImportStoreError && error.code === "invalid_confirmation");
  }
  for (const operation of ["preview", "confirm"] as const) {
    const store = new PostgresPersonalTargetCsvImportStore(async () => {throw Object.assign(new Error("invalid personal target CSV import identity"), {code: "22023"});});
    const call = operation === "preview"
      ? () => store.preview(identity, projectId, rows)
      : () => store.confirm(identity, projectId, confirmInput);
    await assert.rejects(call, (error: unknown) => error instanceof Error && !(error instanceof PersonalTargetCsvImportStoreError) && error.message === "personal target CSV import unavailable");
  }
  await assert.rejects(() => new PostgresPersonalTargetCsvImportStore(async () => {throw Object.assign(new Error("unlisted secret detail"), {code: "22023"});}).preview(identity, projectId, rows), (error: unknown) => error instanceof Error && !error.message.includes("secret"));
});

test("store promise is awaited and receipt PII is never leaked on errors", async () => {
  let settled = false;
  const result = await handlePersonalTargetCsvImportPreview(request(Buffer.from("target_type,display_name,phone,email\nperson,Secret PII,,\n")), dependencies({preview: async () => new Promise((resolve) => setTimeout(() => {settled = true; resolve(previewReceipt);}, 1))}));
  assert.equal(settled, true);
  assert.match(JSON.stringify(result), /Secret PII/);
  const failed = await handlePersonalTargetCsvImportPreview(request(Buffer.from("target_type,display_name,phone,email\nperson,Secret PII,,\n")), dependencies({preview: async () => {throw new Error("Secret PII DB detail");}}));
  assert.equal(failed.status, 503);
  assert.doesNotMatch(JSON.stringify(failed), /Secret PII|DB detail/);
});

const confirmBody = {
  preview_id: previewId,
  request_id: requestId,
  rows,
  actions: ["create", "create"] as const,
};
const confirmInput: PersonalTargetCsvImportConfirmInput = {
  previewId,
  requestId,
  rows,
  actions: ["create", "create"],
};
const dbPreview = {
  contract_id: previewReceipt.contract_id,
  preview_id: previewId,
  row_count: 2,
  hinted_rows: [2],
  previewed_at_utc: previewReceipt.previewed_at_utc,
  expires_at_utc: previewReceipt.expires_at_utc,
};
const dbConfirm = {
  contract_id: confirmReceipt.contract_id,
  preview_id: previewId,
  request_id: requestId,
  outcome: "confirmed",
  row_count: 2,
  hint_count: 1,
  created_count: 2,
  created_targets: [{row_number: 1, target_id: targetId}, {row_number: 2, target_id: confirmReceipt.created_targets[1]?.target_id}],
  completed_at_utc: confirmReceipt.completed_at_utc,
};

function request(body: Buffer, overrides: Partial<Parameters<typeof handlePersonalTargetCsvImportPreview>[0]> = {}): Parameters<typeof handlePersonalTargetCsvImportPreview>[0] {
  return {authorization: "Bearer token", hasQuery: false, hasBody: true, contentType: "text/csv", readBody: async () => body, ...overrides};
}
function confirmRequest(body: Buffer, overrides: Partial<Parameters<typeof handlePersonalTargetCsvImportConfirm>[0]> = {}): Parameters<typeof handlePersonalTargetCsvImportConfirm>[0] {
  return request(body, {contentType: "application/json", ...overrides});
}
type Dependencies = Parameters<typeof handlePersonalTargetCsvImportPreview>[1];
function dependencies(overrides: {
  readonly verify?: Dependencies["identityVerifier"]["verify"];
  readonly loadContext?: Dependencies["contextStore"]["loadOrCreate"];
  readonly preview?: NonNullable<Dependencies["personalTargetCsvImportStore"]>["preview"];
  readonly confirm?: NonNullable<Dependencies["personalTargetCsvImportStore"]>["confirm"];
  readonly store?: Dependencies["personalTargetCsvImportStore"] | undefined;
} = {}): Dependencies {
  const defaultStore = {
    preview: overrides.preview ?? (async () => previewReceipt),
    confirm: overrides.confirm ?? (async () => confirmReceipt),
  };
  const common = {
    identityVerifier: {verify: overrides.verify ?? (async () => identity)},
    contextStore: {loadOrCreate: overrides.loadContext ?? (async () => context)},
  };
  if (Object.hasOwn(overrides, "store")) return overrides.store === undefined ? common : {...common, personalTargetCsvImportStore: overrides.store};
  return {...common, personalTargetCsvImportStore: defaultStore};
}
function invalidStoreError(error: unknown): boolean {
  return error instanceof PersonalTargetCsvImportStoreError && error.code === "invalid_result";
}
