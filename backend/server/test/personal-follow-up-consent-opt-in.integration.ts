import assert from "node:assert/strict";

import {Pool, type PoolClient} from "pg";

import {
  personalFollowUpConsentOptInMetric,
  PostgresPersonalFollowUpConsentOptInStore,
} from "../src/personal-follow-up-consent-opt-in.js";
import {PostgresSessionContextStore} from "../src/session-context.js";

const identity = {
  issuer:
    "https://synthetic-consent-opt-in-adapter-integration.example.test/auth/v1",
  subject: "consent-opt-in-adapter-integration-owner",
};
const requestIds = {
  enable: "e4ad0000-0000-4000-8000-000000000001",
  disable: "e4ad0000-0000-4000-8000-000000000002",
};

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for consent opt-in integration");
}

const pool = new Pool({connectionString: databaseUrl});
const client = await pool.connect();
let transactionOpen = false;

try {
  await client.query("BEGIN");
  transactionOpen = true;
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const contextStore = new PostgresSessionContextStore(query);
  const optInStore = new PostgresPersonalFollowUpConsentOptInStore(query);
  const context = await contextStore.loadOrCreate(identity);
  const projectId = context.current.project.id;

  const unconfigured = await optInStore.read(identity, projectId);
  assert.deepEqual(unconfigured, {
    stateContractId: "project_follow_up_consent_opt_in_state_v1",
    metricId: personalFollowUpConsentOptInMetric,
    projectId: projectId.toLowerCase(),
    status: "not_enabled",
    configuration: null,
  });

  const enabled = await optInStore.configure(identity, projectId, {
    expectedVersion: 0,
    enabled: true,
    requestId: requestIds.enable,
  });
  assert.equal(
    enabled.configurationContractId,
    "project_follow_up_consent_opt_in_configuration_v1",
  );
  assert.equal(enabled.metricId, personalFollowUpConsentOptInMetric);
  assert.equal(enabled.projectId, projectId.toLowerCase());
  assert.equal(enabled.versionNumber, 1);
  assert.equal(enabled.expectedVersion, 0);
  assert.equal(enabled.enabled, true);
  assert.equal(enabled.requestId, requestIds.enable);
  assert.equal(enabled.actorAppUserId, context.appUserId);
  assert.match(enabled.recordedAtUtc, /^\d{4}-\d{2}-\d{2}T.*Z$/);

  const enabledRead = await optInStore.read(identity, projectId);
  assert.equal(enabledRead.status, "enabled");
  assert.deepEqual(enabledRead.configuration, enabled);

  const replay = await optInStore.configure(identity, projectId, {
    expectedVersion: 0,
    enabled: true,
    requestId: requestIds.enable,
  });
  assert.deepEqual(replay, enabled);

  await assertStoreConflictInSavepoint(
    client,
    "consent_opt_in_idempotency_conflict",
    () => optInStore.configure(identity, projectId, {
      expectedVersion: 0,
      enabled: false,
      requestId: requestIds.enable,
    }),
  );
  await assertStoreConflictInSavepoint(
    client,
    "consent_opt_in_stale_conflict",
    () => optInStore.configure(identity, projectId, {
      expectedVersion: 0,
      enabled: false,
      requestId: "e4ad0000-0000-4000-8000-000000000003",
    }),
  );

  const disabled = await optInStore.configure(identity, projectId, {
    expectedVersion: 1,
    enabled: false,
    requestId: requestIds.disable,
  });
  assert.equal(disabled.versionNumber, 2);
  assert.equal(disabled.expectedVersion, 1);
  assert.equal(disabled.enabled, false);

  const disabledRead = await optInStore.read(identity, projectId);
  assert.equal(disabledRead.status, "not_enabled");
  assert.deepEqual(disabledRead.configuration, disabled);
  assert.equal(disabledRead.configuration?.versionNumber, 2);
  assert.equal(disabledRead.configuration?.enabled, false);
  assert.equal(disabledRead.configuration?.requestId, requestIds.disable);

  await client.query("ROLLBACK");
  transactionOpen = false;

  // The adapter writes and the context bootstrap above are both part of the
  // same transaction. A privileged check confirms that rollback removed the
  // append-only configuration rows before a fresh runtime transaction reads
  // the identity again.
  const history = await client.query<{count: string}>(
    `SELECT count(*)::text AS count
       FROM app_private.project_follow_up_consent_opt_in_versions
      WHERE request_id = ANY($1::uuid[])`,
    [[requestIds.enable, requestIds.disable]],
  );
  assert.equal(history.rows[0]?.count, "0");

  await client.query("BEGIN");
  transactionOpen = true;
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");
  const freshQuery = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const freshContextStore = new PostgresSessionContextStore(freshQuery);
  const freshOptInStore = new PostgresPersonalFollowUpConsentOptInStore(
    freshQuery,
  );
  const freshContext = await freshContextStore.loadOrCreate(identity);
  const afterRollback = await freshOptInStore.read(
    identity,
    freshContext.current.project.id,
  );
  assert.equal(afterRollback.status, "not_enabled");
  assert.equal(afterRollback.configuration, null);

  process.stdout.write(
    "Backend personal consent opt-in adapter integration: passed\n",
  );
} finally {
  try {
    if (transactionOpen) await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}

async function assertStoreConflict(operation: Promise<unknown>): Promise<void> {
  await assert.rejects(operation, (error: unknown) => {
    assert.ok(error instanceof Error);
    assert.equal((error as {readonly code?: unknown}).code, "conflict");
    return true;
  });
}

async function assertStoreConflictInSavepoint(
  client: PoolClient,
  savepoint: string,
  operation: () => Promise<unknown>,
): Promise<void> {
  await client.query(`SAVEPOINT ${savepoint}`);
  try {
    await assertStoreConflict(operation());
  } finally {
    await client.query(`ROLLBACK TO SAVEPOINT ${savepoint}`);
    await client.query(`RELEASE SAVEPOINT ${savepoint}`);
  }
}
