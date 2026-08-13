import assert from "node:assert/strict";
import test from "node:test";

import {
  currentRelationshipStageContract,
  currentRelationshipStageStatisticalUnit,
  PersonalCurrentRelationshipStageStoreError,
  PostgresPersonalCurrentRelationshipStageStore,
  readPersonalCurrentRelationshipStage,
  type PersonalCurrentRelationshipStageDependencies,
  type PersonalCurrentRelationshipStageSnapshot,
  type PersonalCurrentRelationshipStageStore,
} from "../src/personal-current-relationship-stage.js";
import type {
  SessionContext,
  SessionContextStore,
} from "../src/session-context.js";

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
  capabilities: [],
};

const snapshot: PersonalCurrentRelationshipStageSnapshot = {
  contractId: currentRelationshipStageContract,
  statisticalUnit: currentRelationshipStageStatisticalUnit,
  projectKey: context.current.project.id,
  snapshotAsOfUtc: "2030-01-15T12:00:00.000Z",
  sourceCutoffUtc: "2030-01-15T11:00:00.000Z",
  authorizedAtUtc: "2030-01-15T12:00:00.000Z",
  coverage: {total: 1, pending: 0},
  relationships: [{
    targetKey: "55555555-5555-4555-8555-555555555555",
    stage: 4,
    revision: 2,
    updatedAtUtc: "2030-01-15T11:00:00.000Z",
  }],
};

test("current relationship read uses verified context without manager capability", async () => {
  let receivedContext: SessionContext | undefined;
  const result = await readPersonalCurrentRelationshipStage(
    "Bearer token",
    dependencies({
      read: async (value) => {
        receivedContext = value;
        return snapshot;
      },
    }),
  );

  assert.equal(result.status, 200);
  assert.equal(receivedContext, context);
  assert.deepEqual(result.body, {
    snapshot: {
      contract_id: currentRelationshipStageContract,
      statistical_unit: currentRelationshipStageStatisticalUnit,
      project_key: context.current.project.id,
      snapshot_as_of_utc: snapshot.snapshotAsOfUtc,
      source_cutoff_utc: snapshot.sourceCutoffUtc,
      authorized_at_utc: snapshot.authorizedAtUtc,
      coverage: {total: 1, pending: 0},
      relationships: [{
        target_key: snapshot.relationships[0]?.targetKey,
        stage: 4,
        revision: 2,
        updated_at_utc: "2030-01-15T11:00:00.000Z",
      }],
    },
  });
});

test("missing bearer token does not load context or snapshot", async () => {
  let contextLoads = 0;
  let snapshotReads = 0;
  const result = await readPersonalCurrentRelationshipStage(
    undefined,
    dependencies({
      loadContext: async () => {
        contextLoads++;
        return context;
      },
      read: async () => {
        snapshotReads++;
        return snapshot;
      },
    }),
  );

  assert.deepEqual(result, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
  assert.equal(contextLoads, 0);
  assert.equal(snapshotReads, 0);
});

test("snapshot store maps forbidden and invalid results to stable failures", async () => {
  const forbidden = await readPersonalCurrentRelationshipStage(
    "Bearer token",
    dependencies({
      read: async () => {
        throw new PersonalCurrentRelationshipStageStoreError("forbidden");
      },
    }),
  );
  const invalid = await readPersonalCurrentRelationshipStage(
    "Bearer token",
    dependencies({
      read: async () => {
        throw new PersonalCurrentRelationshipStageStoreError("invalid");
      },
    }),
  );

  assert.deepEqual(forbidden, {
    status: 403,
    body: {error: {code: "personal_current_relationship_stage_forbidden"}},
  });
  assert.deepEqual(invalid, {
    status: 503,
    body: {error: {code: "personal_current_relationship_stage_unavailable"}},
  });
});

test("Postgres store binds only trusted user, workspace, and project", async () => {
  let sql = "";
  let values: readonly unknown[] = [];
  const store = new PostgresPersonalCurrentRelationshipStageStore(
    async (text, parameters) => {
      sql = text;
      values = parameters;
      return {rows: [{snapshot: databaseSnapshot}]};
    },
  );

  const result = await store.read(context);

  assert.match(sql, /read_personal_current_relationship_stage_snapshot/);
  assert.match(sql, /\$1::uuid, \$2::uuid, \$3::uuid/);
  assert.doesNotMatch(sql, /from_utc|until_utc|as_of|request_body/i);
  assert.deepEqual(values, [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
  ]);
  assert.equal(result.coverage.total, 1);
  assert.equal(result.relationships[0]?.stage, 4);
});

test("Postgres store rejects duplicate rows, PII, and inconsistent metadata", async () => {
  const duplicate = {
    ...databaseSnapshot,
    relationships: [
      ...databaseSnapshot.relationships,
      databaseSnapshot.relationships[0],
    ],
  };
  const pII = {
    ...databaseSnapshot,
    relationships: [{
      ...databaseSnapshot.relationships[0],
      display_name: "should-not-be-accepted",
    }],
  };
  const futureRow = {
    ...databaseSnapshot,
    relationships: [{
      ...databaseSnapshot.relationships[0],
      updated_at_utc: "2030-01-16T00:00:00.000Z",
    }],
  };

  for (const invalid of [duplicate, pII, futureRow]) {
    const store = new PostgresPersonalCurrentRelationshipStageStore(
      async () => ({rows: [{snapshot: invalid}]}),
    );
    await assert.rejects(
      () => store.read(context),
      (error: unknown) =>
        error instanceof PersonalCurrentRelationshipStageStoreError &&
        error.code === "invalid",
    );
  }
});

test("empty snapshot keeps metadata and zero coverage", async () => {
  const empty = {
    ...databaseSnapshot,
    source_cutoff_utc: databaseSnapshot.snapshot_as_of_utc,
    coverage: {total: 0, pending: 0},
    relationships: [],
  };
  const store = new PostgresPersonalCurrentRelationshipStageStore(
    async () => ({rows: [{snapshot: empty}]}),
  );
  const result = await store.read(context);
  assert.equal(result.coverage.total, 0);
  assert.deepEqual(result.relationships, []);
  assert.equal(result.snapshotAsOfUtc, result.sourceCutoffUtc);
});

function dependencies(overrides: {
  readonly read?: PersonalCurrentRelationshipStageStore["read"];
  readonly loadContext?: SessionContextStore["loadOrCreate"];
} = {}): PersonalCurrentRelationshipStageDependencies {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: overrides.loadContext ?? (async () => context),
    },
    snapshotStore: {
      read: overrides.read ?? (async () => snapshot),
    },
  };
}

const databaseSnapshot = {
  contract_id: currentRelationshipStageContract,
  statistical_unit: currentRelationshipStageStatisticalUnit,
  project_key: context.current.project.id,
  snapshot_as_of_utc: "2030-01-15T12:00:00.000Z",
  source_cutoff_utc: "2030-01-15T11:00:00.000Z",
  authorized_at_utc: "2030-01-15T12:00:00.000Z",
  coverage: {total: 1, pending: 0},
  relationships: [{
    target_key: "55555555-5555-4555-8555-555555555555",
    stage: 4,
    revision: 2,
    updated_at_utc: "2030-01-15T11:00:00.000Z",
  }],
};
