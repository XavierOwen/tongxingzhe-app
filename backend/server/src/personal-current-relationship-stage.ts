import {authorizeContext} from "./authorized-context.js";
import type {IdentityVerifier} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export const currentRelationshipStageContract =
  "current_relationship_stage_distribution@1";
export const currentRelationshipStageStatisticalUnit =
  "targetProjectRelationship";

export interface PersonalCurrentRelationshipStageRow {
  readonly targetKey: string;
  readonly stage: number;
  readonly revision: number;
  readonly updatedAtUtc: string;
}

export interface PersonalCurrentRelationshipStageCoverage {
  readonly total: number;
  readonly pending: number;
}

export interface PersonalCurrentRelationshipStageSnapshot {
  readonly contractId: typeof currentRelationshipStageContract;
  readonly statisticalUnit: typeof currentRelationshipStageStatisticalUnit;
  readonly projectKey: string;
  readonly snapshotAsOfUtc: string;
  readonly sourceCutoffUtc: string;
  readonly authorizedAtUtc: string;
  readonly coverage: PersonalCurrentRelationshipStageCoverage;
  readonly relationships: readonly PersonalCurrentRelationshipStageRow[];
}

export interface PersonalCurrentRelationshipStageStore {
  read(context: SessionContext): Promise<PersonalCurrentRelationshipStageSnapshot>;
}

export interface PersonalCurrentRelationshipStageDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly snapshotStore?: PersonalCurrentRelationshipStageStore;
}

export interface PersonalCurrentRelationshipStageHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function readPersonalCurrentRelationshipStage(
  authorization: string | undefined,
  dependencies: PersonalCurrentRelationshipStageDependencies,
): Promise<PersonalCurrentRelationshipStageHttpResult> {
  const authorized = await authorizeContext(
    authorization,
    dependencies,
    [],
    "personal_current_relationship_stage_unavailable",
  );
  if (authorized.status === "rejected") {
    return failure(authorized.responseStatus, authorized.errorCode);
  }
  if (dependencies.snapshotStore === undefined) {
    return failure(503, "personal_current_relationship_stage_unavailable");
  }

  try {
    const snapshot = await dependencies.snapshotStore.read(authorized.context);
    return {status: 200, body: {snapshot: serializeSnapshot(snapshot)}};
  } catch (error) {
    return storeFailure(error);
  }
}

export type PersonalCurrentRelationshipStageQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresPersonalCurrentRelationshipStageStore
implements PersonalCurrentRelationshipStageStore {
  constructor(private readonly query: PersonalCurrentRelationshipStageQuery) {}

  async read(
    context: SessionContext,
  ): Promise<PersonalCurrentRelationshipStageSnapshot> {
    try {
      const result = await this.query(
        `SELECT app_data.read_personal_current_relationship_stage_snapshot(
           $1::uuid, $2::uuid, $3::uuid
         ) AS snapshot`,
        contextValues(context),
      );
      if (result.rows.length !== 1) {
        throw invalidSnapshot();
      }
      return parseSnapshot(
        rowField(result.rows[0], "snapshot"),
        context.current.project.id,
      );
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class PersonalCurrentRelationshipStageStoreError extends Error {
  constructor(readonly code: "forbidden" | "invalid") {
    super(code);
    this.name = "PersonalCurrentRelationshipStageStoreError";
  }
}

function parseSnapshot(
  value: unknown,
  expectedProjectKey: string,
): PersonalCurrentRelationshipStageSnapshot {
  const root = object(value);
  requireExactKeys(root, [
    "contract_id",
    "statistical_unit",
    "project_key",
    "snapshot_as_of_utc",
    "source_cutoff_utc",
    "authorized_at_utc",
    "coverage",
    "relationships",
  ]);
  if (root.contract_id !== currentRelationshipStageContract) {
    throw invalidSnapshot();
  }
  if (root.statistical_unit !== currentRelationshipStageStatisticalUnit) {
    throw invalidSnapshot();
  }

  const projectKey = uuid(root.project_key);
  if (projectKey !== expectedProjectKey.toLowerCase()) {
    throw invalidSnapshot();
  }
  const snapshotAsOfUtc = utcTimestamp(root.snapshot_as_of_utc);
  const sourceCutoffUtc = utcTimestamp(root.source_cutoff_utc);
  const authorizedAtUtc = utcTimestamp(root.authorized_at_utc);
  const snapshotTime = Date.parse(snapshotAsOfUtc);
  if (
    Date.parse(sourceCutoffUtc) > snapshotTime ||
    Date.parse(authorizedAtUtc) > snapshotTime
  ) {
    throw invalidSnapshot();
  }

  const coverageRoot = object(root.coverage);
  requireExactKeys(coverageRoot, ["total", "pending"]);
  const coverage: PersonalCurrentRelationshipStageCoverage = {
    total: safeInteger(coverageRoot.total, 0),
    pending: safeInteger(coverageRoot.pending, 0),
  };
  if (coverage.pending !== 0) throw invalidSnapshot();

  if (!Array.isArray(root.relationships)) throw invalidSnapshot();
  const targetKeys = new Set<string>();
  const relationships = root.relationships.map((value) => {
    const relationship = parseRelationship(value, snapshotTime, targetKeys);
    targetKeys.add(relationship.targetKey);
    return relationship;
  });
  if (coverage.total !== relationships.length) throw invalidSnapshot();

  return {
    contractId: currentRelationshipStageContract,
    statisticalUnit: currentRelationshipStageStatisticalUnit,
    projectKey,
    snapshotAsOfUtc,
    sourceCutoffUtc,
    authorizedAtUtc,
    coverage,
    relationships,
  };
}

function parseRelationship(
  value: unknown,
  snapshotTime: number,
  targetKeys: ReadonlySet<string>,
): PersonalCurrentRelationshipStageRow {
  const root = object(value);
  requireExactKeys(root, [
    "target_key",
    "stage",
    "revision",
    "updated_at_utc",
  ]);
  const targetKey = uuid(root.target_key);
  if (targetKeys.has(targetKey)) throw invalidSnapshot();
  const stage = safeInteger(root.stage, 0, 4);
  const revision = safeInteger(root.revision, 1);
  const updatedAtUtc = utcTimestamp(root.updated_at_utc);
  if (Date.parse(updatedAtUtc) > snapshotTime) throw invalidSnapshot();
  return {targetKey, stage, revision, updatedAtUtc};
}

function serializeSnapshot(
  snapshot: PersonalCurrentRelationshipStageSnapshot,
): Readonly<Record<string, unknown>> {
  return {
    contract_id: snapshot.contractId,
    statistical_unit: snapshot.statisticalUnit,
    project_key: snapshot.projectKey,
    snapshot_as_of_utc: snapshot.snapshotAsOfUtc,
    source_cutoff_utc: snapshot.sourceCutoffUtc,
    authorized_at_utc: snapshot.authorizedAtUtc,
    coverage: {
      total: snapshot.coverage.total,
      pending: snapshot.coverage.pending,
    },
    relationships: snapshot.relationships.map((relationship) => ({
      target_key: relationship.targetKey,
      stage: relationship.stage,
      revision: relationship.revision,
      updated_at_utc: relationship.updatedAtUtc,
    })),
  };
}

function storeFailure(
  error: unknown,
): PersonalCurrentRelationshipStageHttpResult {
  if (error instanceof PersonalCurrentRelationshipStageStoreError) {
    if (error.code === "forbidden") {
      return failure(403, "personal_current_relationship_stage_forbidden");
    }
  }
  return failure(503, "personal_current_relationship_stage_unavailable");
}

function mapPostgresError(error: unknown): Error {
  const code = record(error).code;
  if (code === "42501") {
    return new PersonalCurrentRelationshipStageStoreError("forbidden");
  }
  if (code === "22023" || code === "23514") {
    return new PersonalCurrentRelationshipStageStoreError("invalid");
  }
  return error instanceof Error ? error : new Error(String(error));
}

function contextValues(context: SessionContext): readonly string[] {
  return [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
  ];
}

function rowField(row: unknown, field: string): unknown {
  const root = object(row);
  if (!(field in root)) throw invalidSnapshot();
  return root[field];
}

function object(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidSnapshot();
  }
  return value as Record<string, unknown>;
}

function requireExactKeys(
  value: Readonly<Record<string, unknown>>,
  expected: readonly string[],
): void {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  if (
    actual.length !== sortedExpected.length ||
    actual.some((key, index) => key !== sortedExpected[index])
  ) {
    throw invalidSnapshot();
  }
}

function uuid(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw invalidSnapshot();
  }
  return value.toLowerCase();
}

function safeInteger(value: unknown, minimum: number, maximum = Number.MAX_SAFE_INTEGER): number {
  if (
    !Number.isSafeInteger(value) ||
    Number(value) < minimum ||
    Number(value) > maximum
  ) {
    throw invalidSnapshot();
  }
  return Number(value);
}

function utcTimestamp(value: unknown): string {
  if (typeof value !== "string" || !rfc3339Pattern.test(value)) {
    throw invalidSnapshot();
  }
  const timestamp = new Date(value);
  if (!Number.isFinite(timestamp.valueOf())) throw invalidSnapshot();
  return timestamp.toISOString();
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function invalidSnapshot(): PersonalCurrentRelationshipStageStoreError {
  return new PersonalCurrentRelationshipStageStoreError("invalid");
}

function failure(
  status: number,
  code: string,
): PersonalCurrentRelationshipStageHttpResult {
  return {status, body: {error: {code}}};
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const rfc3339Pattern =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
