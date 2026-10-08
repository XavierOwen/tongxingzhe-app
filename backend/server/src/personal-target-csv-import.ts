import {bearerToken} from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
  type VerifiedIdentity,
} from "./identity.js";
import type {SessionContextStore} from "./session-context.js";

export const personalTargetCsvImportPreviewContract =
  "personal-target-csv-import-preview:v1";
export const personalTargetCsvImportConfirmContract =
  "personal-target-csv-import-confirm:v1";
export const personalTargetCsvImportCapability = "import_target_pii";
export const personalTargetCsvImportMaxRows = 500;

export interface PersonalTargetCsvImportRow {
  readonly target_type: "person" | "institution";
  readonly display_name: string;
  readonly phone: string | null;
  readonly email: string | null;
}

export interface PersonalTargetCsvImportIssue {
  readonly row_number: number;
  readonly field: string;
  readonly code: string;
}

export interface PersonalTargetCsvImportPreviewReceipt {
  readonly contract_id: typeof personalTargetCsvImportPreviewContract;
  readonly preview_id: string;
  readonly row_count: number;
  readonly hinted_rows: readonly number[];
  readonly previewed_at_utc: string;
  readonly expires_at_utc: string;
}

export interface PersonalTargetCsvImportCreatedTarget {
  readonly row_number: number;
  readonly target_id: string;
}

export interface PersonalTargetCsvImportConfirmReceipt {
  readonly contract_id: typeof personalTargetCsvImportConfirmContract;
  readonly preview_id: string;
  readonly request_id: string;
  readonly outcome: "confirmed" | "stale_preview";
  readonly row_count: number;
  readonly hint_count: number;
  readonly created_count: number;
  readonly created_targets: readonly PersonalTargetCsvImportCreatedTarget[];
  readonly completed_at_utc: string;
}

export type PersonalTargetCsvImportAction =
  | "skip"
  | "create"
  | "create_separate";

export interface PersonalTargetCsvImportConfirmInput {
  readonly previewId: string;
  readonly requestId: string;
  readonly rows: readonly PersonalTargetCsvImportRow[];
  readonly actions: readonly PersonalTargetCsvImportAction[];
}

export interface PersonalTargetCsvImportStore {
  preview(
    identity: VerifiedIdentity,
    projectId: string,
    rows: readonly PersonalTargetCsvImportRow[],
  ): Promise<PersonalTargetCsvImportPreviewReceipt>;
  confirm(
    identity: VerifiedIdentity,
    projectId: string,
    input: PersonalTargetCsvImportConfirmInput,
  ): Promise<PersonalTargetCsvImportConfirmReceipt>;
}

export type PersonalTargetCsvImportQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalTargetCsvImportStore
implements PersonalTargetCsvImportStore {
  constructor(private readonly query: PersonalTargetCsvImportQuery) {}

  async preview(
    identity: VerifiedIdentity,
    projectId: string,
    rows: readonly PersonalTargetCsvImportRow[],
  ): Promise<PersonalTargetCsvImportPreviewReceipt> {
    try {
      const result = await this.query(
        `SELECT contract_id, preview_id, row_count, hinted_rows, previewed_at_utc, expires_at_utc
         FROM app_data.preview_personal_target_csv_import_v1(
           $1::text, $2::text, $3::uuid, $4::jsonb
         )`,
        [identity.issuer, identity.subject, projectId, JSON.stringify(rows)],
      );
      if (result.rows.length !== 1) throw invalidResult();
      const receipt = parsePreviewReceipt(result.rows[0]);
      if (receipt.row_count !== rows.length) throw invalidResult();
      return receipt;
    } catch (error) {
      throw mapDatabaseError(error, "preview");
    }
  }

  async confirm(
    identity: VerifiedIdentity,
    projectId: string,
    input: PersonalTargetCsvImportConfirmInput,
  ): Promise<PersonalTargetCsvImportConfirmReceipt> {
    try {
      const result = await this.query(
        `SELECT contract_id, preview_id, request_id, outcome, row_count, hint_count, created_count, created_targets, completed_at_utc
         FROM app_data.confirm_personal_target_csv_import_v1(
           $1::text, $2::text, $3::uuid, $4::uuid, $5::uuid, $6::jsonb, $7::jsonb
         )`,
        [
          identity.issuer,
          identity.subject,
          projectId,
          input.previewId,
          input.requestId,
          JSON.stringify(input.rows),
          JSON.stringify(input.actions),
        ],
      );
      if (result.rows.length !== 1) throw invalidResult();
      const receipt = parseConfirmReceipt(result.rows[0]);
      if (
        receipt.preview_id !== input.previewId ||
        receipt.request_id !== input.requestId ||
        receipt.row_count !== input.rows.length ||
        receipt.created_count !== (receipt.outcome === "confirmed"
          ? input.actions.filter((action) => action !== "skip").length
          : 0) ||
        (receipt.outcome === "confirmed" && !sameNumbers(
          receipt.created_targets.map((item) => item.row_number),
          input.actions.flatMap((action, index) => action === "skip" ? [] : [index + 1]),
        ))
      ) throw invalidResult();
      return receipt;
    } catch (error) {
      throw mapDatabaseError(error, "confirm");
    }
  }
}

export interface PersonalTargetCsvImportRequest {
  readonly authorization: string | undefined;
  readonly hasQuery: boolean;
  readonly hasBody: boolean;
  readonly contentType: string | undefined;
  readonly readBody: () => Promise<Buffer>;
}

export interface PersonalTargetCsvImportDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly personalTargetCsvImportStore?: PersonalTargetCsvImportStore;
}

export interface PersonalTargetCsvImportHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function handlePersonalTargetCsvImportPreview(
  request: PersonalTargetCsvImportRequest,
  dependencies: PersonalTargetCsvImportDependencies,
): Promise<PersonalTargetCsvImportHttpResult> {
  const authorized = await authorize(request, dependencies);
  if ("status" in authorized) return authorized;
  if (request.hasQuery || !request.hasBody) return failure(400, "invalid_personal_target_csv_import_request");
  if (mediaType(request.contentType) !== "text/csv") return failure(415, "unsupported_personal_target_csv_import_media_type");
  const store = dependencies.personalTargetCsvImportStore;
  if (store === undefined) return failure(503, "personal_target_csv_import_unavailable");
  const parsed = parsePersonalTargetCsv(await request.readBody());
  if (parsed.issues.length > 0) return {status: 422, body: {error: {code: "invalid_personal_target_csv_import_rows", issues: parsed.issues}}};
  try {
    const receipt = await store.preview(
      authorized.identity,
      authorized.projectId,
      parsed.rows,
    );
    const hinted = new Set(receipt.hinted_rows);
    return {
      status: 200,
      body: {
        receipt,
        rows: parsed.rows.map((row, index) => ({
          row_number: index + 1,
          ...row,
          hinted: hinted.has(index + 1),
        })),
      },
    };
  } catch (error) {
    return storeFailure(error, "preview");
  }
}

export async function handlePersonalTargetCsvImportConfirm(
  request: PersonalTargetCsvImportRequest,
  dependencies: PersonalTargetCsvImportDependencies,
): Promise<PersonalTargetCsvImportHttpResult> {
  const authorized = await authorize(request, dependencies);
  if ("status" in authorized) return authorized;
  if (request.hasQuery || !request.hasBody) return failure(400, "invalid_personal_target_csv_import_request");
  if (mediaType(request.contentType) !== "application/json") return failure(415, "unsupported_personal_target_csv_import_media_type");
  const store = dependencies.personalTargetCsvImportStore;
  if (store === undefined) return failure(503, "personal_target_csv_import_unavailable");
  const input = parseConfirmInput(await request.readBody());
  if (input === null) return failure(400, "invalid_personal_target_csv_import_request");
  try {
    const receipt = await store.confirm(authorized.identity, authorized.projectId, input);
    return receipt.outcome === "stale_preview"
      ? {status: 409, body: {receipt}}
      : {status: 200, body: {receipt}};
  } catch (error) {
    return storeFailure(error, "confirm");
  }
}

interface AuthorizedScope {
  readonly identity: VerifiedIdentity;
  readonly projectId: string;
}

async function authorize(
  request: PersonalTargetCsvImportRequest,
  dependencies: PersonalTargetCsvImportDependencies,
): Promise<AuthorizedScope | PersonalTargetCsvImportHttpResult> {
  const token = bearerToken(request.authorization);
  if (token === null) return failure(401, "unauthenticated");
  let identity: VerifiedIdentity;
  try {
    identity = await dependencies.identityVerifier.verify(token);
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "personal_target_csv_import_unavailable");
  }
  try {
    const context = await dependencies.contextStore.loadOrCreate(identity);
    if (context.current.workspace.kind !== "personal") return failure(403, "personal_target_csv_import_forbidden");
    if (!context.capabilities.includes(personalTargetCsvImportCapability)) return failure(403, "personal_target_csv_import_forbidden");
    return {identity, projectId: context.current.project.id};
  } catch (error) {
    return databaseScopeForbidden(error) ? failure(403, "personal_target_csv_import_forbidden") : failure(503, "personal_target_csv_import_unavailable");
  }
}

export interface ParseCsvResult {
  readonly rows: readonly PersonalTargetCsvImportRow[];
  readonly issues: readonly PersonalTargetCsvImportIssue[];
}

export function parsePersonalTargetCsv(value: Buffer): ParseCsvResult {
  let text: string;
  try {
    text = new TextDecoder("utf-8", {fatal: true}).decode(value);
  } catch {
    return {rows: [], issues: [{row_number: 1, field: "csv", code: "invalid_utf8"}]};
  }
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const records = parseCsvRecords(text);
  if (records === null) return {rows: [], issues: [{row_number: 1, field: "csv", code: "malformed_csv"}]};
  if (records.length === 0 || !sameStrings(records[0] ?? [], ["target_type", "display_name", "phone", "email"])) {
    return {rows: [], issues: [{row_number: 1, field: "header", code: "invalid_header"}]};
  }
  const data = records.slice(1);
  if (data.length > personalTargetCsvImportMaxRows) {
    return {rows: [], issues: [{row_number: personalTargetCsvImportMaxRows + 1, field: "row", code: "too_many_rows"}]};
  }
  const rows: PersonalTargetCsvImportRow[] = [];
  const issues: PersonalTargetCsvImportIssue[] = [];
  data.forEach((cells, index) => {
    const rowNumber = index + 1;
    if (cells.length !== 4) {
      issues.push({row_number: rowNumber, field: "row", code: "invalid_column_count"});
      return;
    }
    const [type, rawName, rawPhone, rawEmail] = cells as [string, string, string, string];
    const targetType = type === "person" || type === "institution" ? type : null;
    const displayName = rawName.trim();
    const phone = rawPhone.trim() || null;
    const email = rawEmail.trim() || null;
    let valid = true;
    if (targetType === null) { issues.push({row_number: rowNumber, field: "target_type", code: "invalid_value"}); valid = false; }
    const nameLength = [...displayName].length;
    if (nameLength < 1 || nameLength > 200) { issues.push({row_number: rowNumber, field: "display_name", code: "invalid_length"}); valid = false; }
    if (phone !== null && [...phone].length > 80) { issues.push({row_number: rowNumber, field: "phone", code: "invalid_length"}); valid = false; }
    if (email !== null && [...email].length > 320) { issues.push({row_number: rowNumber, field: "email", code: "invalid_length"}); valid = false; }
    if (valid && targetType !== null) rows.push({target_type: targetType, display_name: displayName, phone, email});
  });
  return {rows, issues};
}

function parseCsvRecords(text: string): string[][] | null {
  const records: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  let afterQuote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i] as string;
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else { quoted = false; afterQuote = true; }
      } else if (ch === "\r") {
        if (text[i + 1] !== "\n") return null;
        field += "\r\n";
        i++;
      } else field += ch;
      continue;
    }
    if (afterQuote) {
      if (ch === ",") { row.push(field); field = ""; afterQuote = false; }
      else if (ch === "\n") { row.push(field); records.push(row); row = []; field = ""; afterQuote = false; }
      else if (ch === "\r" && text[i + 1] === "\n") { i++; row.push(field); records.push(row); row = []; field = ""; afterQuote = false; }
      else return null;
      continue;
    }
    if (ch === '"') {
      if (field.length !== 0) return null;
      quoted = true;
    } else if (ch === ",") { row.push(field); field = ""; }
    else if (ch === "\n") { row.push(field); records.push(row); row = []; field = ""; }
    else if (ch === "\r") {
      if (text[i + 1] !== "\n") return null;
      i++; row.push(field); records.push(row); row = []; field = "";
    } else field += ch;
  }
  if (quoted) return null;
  if (field !== "" || row.length > 0 || afterQuote) { row.push(field); records.push(row); }
  return records;
}

function parseConfirmInput(value: Buffer): PersonalTargetCsvImportConfirmInput | null {
  const root = jsonObject(value);
  if (root === null || !exactKeys(root, ["preview_id", "request_id", "rows", "actions"])) return null;
  const previewId = strictUuid(root.preview_id);
  const requestId = strictUuid(root.request_id);
  if (previewId === null || requestId === null || !Array.isArray(root.rows) || !Array.isArray(root.actions) || root.rows.length > personalTargetCsvImportMaxRows || root.actions.length !== root.rows.length) return null;
  const rows: PersonalTargetCsvImportRow[] = [];
  for (const value of root.rows) {
    const row = jsonRecord(value);
    if (row === null || !exactKeys(row, ["target_type", "display_name", "phone", "email"])) return null;
    const targetType = row.target_type;
    if (targetType !== "person" && targetType !== "institution") return null;
    if (typeof row.display_name !== "string" || typeof row.phone !== "string" && row.phone !== null || typeof row.email !== "string" && row.email !== null) return null;
    const name = row.display_name.trim();
    const phone = typeof row.phone === "string" ? row.phone.trim() || null : null;
    const email = typeof row.email === "string" ? row.email.trim() || null : null;
    if ([...name].length < 1 || [...name].length > 200 || (phone !== null && [...phone].length > 80) || (email !== null && [...email].length > 320)) return null;
    rows.push({target_type: targetType, display_name: name, phone, email});
  }
  const actions = root.actions as unknown[];
  if (!actions.every((action) => action === "skip" || action === "create" || action === "create_separate")) return null;
  return {previewId, requestId, rows, actions: actions as PersonalTargetCsvImportAction[]};
}

function parsePreviewReceipt(value: unknown): PersonalTargetCsvImportPreviewReceipt {
  const root = jsonRecord(value);
  if (root === null || !exactKeys(root, ["contract_id", "preview_id", "row_count", "hinted_rows", "previewed_at_utc", "expires_at_utc"]) || root.contract_id !== personalTargetCsvImportPreviewContract) throw invalidResult();
  const previewId = strictUuid(root.preview_id);
  const rowCount = count(root.row_count);
  if (previewId === null || rowCount === null || !Array.isArray(root.hinted_rows) || !root.hinted_rows.every((x) => Number.isInteger(x) && (x as number) >= 1 && (x as number) <= rowCount)) throw invalidResult();
  const hinted = root.hinted_rows as number[];
  const previewed = timestamp(root.previewed_at_utc);
  const expires = timestamp(root.expires_at_utc);
  if (new Set(hinted).size !== hinted.length || hinted.some((row, index) => index > 0 && row <= (hinted[index - 1] as number)) || previewed === null || expires === null || timestampMicros(expires) - timestampMicros(previewed) !== 900_000_000n) throw invalidResult();
  return {contract_id: personalTargetCsvImportPreviewContract, preview_id: previewId, row_count: rowCount, hinted_rows: hinted, previewed_at_utc: previewed, expires_at_utc: expires};
}

function parseConfirmReceipt(value: unknown): PersonalTargetCsvImportConfirmReceipt {
  const root = jsonRecord(value);
  if (root === null || !exactKeys(root, ["contract_id", "preview_id", "request_id", "outcome", "row_count", "hint_count", "created_count", "created_targets", "completed_at_utc"]) || root.contract_id !== personalTargetCsvImportConfirmContract || root.outcome !== "confirmed" && root.outcome !== "stale_preview") throw invalidResult();
  const previewId = strictUuid(root.preview_id);
  const requestId = strictUuid(root.request_id);
  const rowCount = count(root.row_count);
  const hintCount = count(root.hint_count);
  const createdCount = count(root.created_count);
  const completed = timestamp(root.completed_at_utc);
  if (previewId === null || requestId === null || rowCount === null || hintCount === null || hintCount > rowCount || createdCount === null || !Array.isArray(root.created_targets) || completed === null) throw invalidResult();
  const created: PersonalTargetCsvImportCreatedTarget[] = [];
  for (const item of root.created_targets) {
    const target = jsonRecord(item);
    if (target === null || !exactKeys(target, ["row_number", "target_id"]) || !Number.isInteger(target.row_number) || (target.row_number as number) < 1 || (target.row_number as number) > rowCount) throw invalidResult();
    const targetId = strictUuid(target.target_id);
    if (targetId === null) throw invalidResult();
    created.push({row_number: target.row_number as number, target_id: targetId});
  }
  if (created.length !== createdCount || (root.outcome === "stale_preview" && createdCount !== 0) || new Set(created.map((item) => item.row_number)).size !== created.length || new Set(created.map((item) => item.target_id)).size !== created.length || created.some((item, index) => index > 0 && item.row_number <= (created[index - 1] as PersonalTargetCsvImportCreatedTarget).row_number)) throw invalidResult();
  return {contract_id: personalTargetCsvImportConfirmContract, preview_id: previewId, request_id: requestId, outcome: root.outcome, row_count: rowCount, hint_count: hintCount, created_count: createdCount, created_targets: created, completed_at_utc: completed};
}

function storeFailure(error: unknown, operation: "preview" | "confirm"): PersonalTargetCsvImportHttpResult {
  if (error instanceof PersonalTargetCsvImportStoreError) {
    if (error.code === "forbidden") return failure(403, "personal_target_csv_import_forbidden");
    if (error.code === "invalid_rows") return operation === "preview" ? failure(422, "invalid_personal_target_csv_import_rows") : failure(400, "invalid_personal_target_csv_import_request");
    if (error.code === "invalid_confirmation") return failure(400, "invalid_personal_target_csv_import_request");
    if (error.code === "conflict") return failure(409, "personal_target_csv_import_conflict");
  }
  return failure(503, "personal_target_csv_import_unavailable");
}

export class PersonalTargetCsvImportStoreError extends Error {
  constructor(readonly code: "forbidden" | "invalid_result" | "invalid_rows" | "invalid_confirmation" | "conflict") {
    super(code);
    this.name = "PersonalTargetCsvImportStoreError";
  }
}

function mapDatabaseError(error: unknown, operation: "preview" | "confirm"): unknown {
  if (error instanceof PersonalTargetCsvImportStoreError) return error;
  const root = jsonRecord(error);
  const code = root?.code;
  const message = root?.message;
  if (code === "42501" && message === "personal target CSV import scope is forbidden") return new PersonalTargetCsvImportStoreError("forbidden");
  if (code === "22023" && message === "invalid personal target CSV import rows") return new PersonalTargetCsvImportStoreError("invalid_rows");
  if (code === "22023" && message === "invalid personal target CSV import identity") return new Error("personal target CSV import unavailable");
  if (operation === "confirm" && code === "22023" && [
    "invalid personal target CSV import actions",
    "invalid personal target CSV import request",
    "invalid personal target CSV import confirmation",
  ].includes(String(message))) return new PersonalTargetCsvImportStoreError("invalid_confirmation");
  if (code === "23505" && message === "personal target CSV import request conflict") return new PersonalTargetCsvImportStoreError("conflict");
  return new Error("personal target CSV import unavailable");
}

function databaseScopeForbidden(value: unknown): boolean {
  const root = jsonRecord(value);
  return root?.code === "42501" && [
    "trusted identity is not mapped to an active app user",
    "mapped app user is not active",
  ].includes(String(root.message));
}

function mediaType(value: string | undefined): string | null {
  return typeof value === "string" ? value.split(";", 1)[0]?.trim().toLowerCase() ?? null : null;
}
function jsonObject(value: Buffer): Record<string, unknown> | null {
  try { return jsonRecord(JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(value))); } catch { return null; }
}
function jsonRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
function exactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const keys = Object.keys(value).sort();
  const sorted = [...expected].sort();
  return keys.length === sorted.length && keys.every((key, i) => key === sorted[i]);
}
function sameStrings(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}
function sameNumbers(left: readonly number[], right: readonly number[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}
function strictUuid(value: unknown): string | null {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value) ? value : null;
}
function count(value: unknown): number | null {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : null;
}
function timestamp(value: unknown): string | null {
  if (value instanceof Date) return Number.isFinite(value.valueOf()) ? value.toISOString().replace(/\.(\d{3})Z$/, (_match, millis: string) => `.${millis}000Z`) : null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/.test(value)) return null;
  const date = new Date(`${value.slice(0, 19)}.${value.slice(20, 23)}Z`);
  return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 23) === value.slice(0, 23) ? value : null;
}
function timestampMicros(value: string): bigint {
  return BigInt(Date.parse(`${value.slice(0, 19)}.${value.slice(20, 23)}Z`)) * 1000n + BigInt(value.slice(23, 26));
}
function invalidResult(): PersonalTargetCsvImportStoreError { return new PersonalTargetCsvImportStoreError("invalid_result"); }
function failure(status: number, code: string): PersonalTargetCsvImportHttpResult { return {status, body: {error: {code}}}; }
