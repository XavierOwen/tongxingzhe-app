import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import type {AddressInfo} from "node:net";
import {Pool} from "pg";
import test from "node:test";

import {
  PostgresPersonalTargetPiiExportStore,
} from "../src/personal-target-pii-export.js";
import {PostgresPromotionTargetStore} from "../src/promotion-targets.js";
import {createBackendServer} from "../src/server.js";
import {PostgresSessionContextStore} from "../src/session-context.js";

const databaseUrl = process.env.DATABASE_URL?.trim();

test("personal target PII export returns 0112 bytes and a value-free audit", {
  skip: !databaseUrl,
}, async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  const suffix = randomUUID();
  const baseIdentity = {
    issuer: `https://synthetic-pii-export-${suffix}.example.test/auth/v1`,
    subject: `pii-export-${suffix}`,
  };
  let transactionOpen = false;
  let server: ReturnType<typeof createBackendServer> | undefined;

  try {
    await client.query("BEGIN");
    transactionOpen = true;
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");
    const query = async (text: string, values: readonly unknown[]) =>
      client.query(text, [...values]);
    const contextStore = new PostgresSessionContextStore(query);
    const context = await contextStore.loadOrCreate(baseIdentity);
    assert.equal(context.current.workspace.kind, "personal");
    assert.ok(context.capabilities.includes("export_target_pii"));
    assert.ok(context.capabilities.includes("view_assigned_target_pii"));

    const displayName = `导出对象 “甲” ${suffix}`;
    const phone = "+1 312 555 0539";
    const email = `pii-export-${suffix}@example.test`;
    const targetStore = new PostgresPromotionTargetStore(query);
    const target = await targetStore.create(context, {
      type: "person",
      displayName,
      phone,
      email,
      requestId: randomUUID(),
    });

    const clockResult = await query(
      `SELECT floor(extract(
         epoch FROM transaction_timestamp()
       ))::bigint::text AS unix_seconds`,
      [],
    );
    const passwordAuthenticatedAtUnixSeconds = Number(
      (clockResult.rows[0] as Record<string, unknown>).unix_seconds,
    );
    assert.ok(Number.isSafeInteger(passwordAuthenticatedAtUnixSeconds));
    const identity = {
      ...baseIdentity,
      passwordAuthenticatedAtUnixSeconds,
    };
    server = createBackendServer({
      identityVerifier: {verify: async () => identity},
      contextStore,
      personalTargetPiiExportStore:
        new PostgresPersonalTargetPiiExportStore(query),
    });
    const address = await listen(server);
    const response = await fetch(
      `http://127.0.0.1:${address.port}/v1/promotion-targets/export`,
      {headers: {authorization: "Bearer synthetic-token"}},
    );
    const bytes = Buffer.from(await response.arrayBuffer());

    assert.equal(response.status, 200);
    assert.equal(
      response.headers.get("content-type"),
      "application/json; charset=utf-8",
    );
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.equal(
      response.headers.get("content-disposition"),
      'attachment; filename="personal-promotion-target-pii-v1.json"',
    );
    assert.equal(response.headers.get("content-length"), String(bytes.byteLength));

    const document = JSON.parse(bytes.toString("utf8")) as Record<string, unknown>;
    assert.deepEqual(Object.keys(document), [
      "export_contract_id",
      "export_event_id",
      "exported_at_utc",
      "targets",
    ]);
    assert.equal(
      document.export_contract_id,
      "personal_promotion_target_pii_export_v1",
    );
    assert.match(
      String(document.exported_at_utc),
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/,
    );
    assert.deepEqual(document.targets, [{
      target_type: "person",
      display_name: displayName,
      phone,
      email,
    }]);

    await client.query("RESET ROLE");
    const auditResult = await client.query(
      `SELECT event_row.*,
              pg_catalog.row_to_json(event_row)::text AS row_json
         FROM app_private.personal_target_pii_export_events AS event_row
        WHERE event_row.export_event_id = $1::uuid`,
      [document.export_event_id],
    );
    assert.equal(auditResult.rowCount, 1);
    const audit = auditResult.rows[0] as Record<string, unknown>;
    assert.equal(audit.actor_app_user_id, context.appUserId);
    assert.equal(audit.workspace_id, context.current.workspace.id);
    assert.equal(
      audit.export_contract_id,
      "personal_promotion_target_pii_export_v1",
    );
    assert.equal(audit.authentication_method, "password");
    assert.equal(audit.result, "prepared");
    assert.equal(audit.target_count, 1);
    assert.equal(audit.byte_count, bytes.byteLength);
    assert.doesNotMatch(
      String(audit.row_json),
      new RegExp([
        escapeRegExp(target.id),
        escapeRegExp(displayName),
        escapeRegExp(phone),
        escapeRegExp(email),
      ].join("|")),
    );

    process.stdout.write("Personal target PII export HTTP integration: passed\n");
  } finally {
    try {
      if (server !== undefined) await close(server);
    } finally {
      try {
        if (transactionOpen) await client.query("ROLLBACK");
      } finally {
        client.release();
        await pool.end();
      }
    }
  }
});

async function listen(
  server: ReturnType<typeof createBackendServer>,
): Promise<{port: number}> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  return {port: (address as AddressInfo).port};
}

async function close(
  server: ReturnType<typeof createBackendServer>,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
