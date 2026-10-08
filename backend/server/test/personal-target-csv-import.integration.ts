import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {Pool} from "pg";
import test from "node:test";

import {PostgresPersonalTargetCsvImportStore} from "../src/personal-target-csv-import.js";
import {PostgresSessionContextStore} from "../src/session-context.js";
import {createBackendServer} from "../src/server.js";

const databaseUrl = process.env.DATABASE_URL?.trim();

test("personal target CSV import persists only selected targets through HTTP", {
  skip: !databaseUrl,
}, async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  const suffix = randomUUID();
  const identity = {
    issuer: `https://synthetic-csv-import-${suffix}.example.test/auth/v1`,
    subject: `csv-import-${suffix}`,
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
    const context = await contextStore.loadOrCreate(identity);
    const serverStore = new PostgresPersonalTargetCsvImportStore(query);
    server = createBackendServer({
      identityVerifier: {verify: async () => identity},
      contextStore,
      personalTargetCsvImportStore: serverStore,
    });
    const address = await listen(server);
    const baseUrl = `http://127.0.0.1:${address.port}`;
    const csv = [
      "target_type,display_name,phone,email",
      "person,  CSV Import Created  , 312-555-0191 , created@example.test ",
      "institution,CSV Import Skipped,312-555-0192,skipped@example.test",
    ].join("\n");
    const previewResponse = await fetch(
      `${baseUrl}/v1/promotion-targets/imports/csv/preview`,
      {
        method: "POST",
        headers: {
          authorization: "Bearer synthetic-token",
          "content-type": "text/csv; charset=utf-8",
        },
        body: csv,
      },
    );
    assert.equal(previewResponse.status, 200);
    const preview = await previewResponse.json() as {
      receipt: {preview_id: string; row_count: number};
      rows: Array<Record<string, unknown>>;
    };
    assert.equal(preview.receipt.row_count, 2);
    assert.equal(preview.rows.length, 2);
    assert.deepEqual(preview.rows.map(({row_number, target_type, display_name, phone, email}) =>
      ({row_number, target_type, display_name, phone, email})), [
      {
        row_number: 1,
        target_type: "person",
        display_name: "CSV Import Created",
        phone: "312-555-0191",
        email: "created@example.test",
      },
      {
        row_number: 2,
        target_type: "institution",
        display_name: "CSV Import Skipped",
        phone: "312-555-0192",
        email: "skipped@example.test",
      },
    ]);

    const confirmBody = {
      preview_id: preview.receipt.preview_id,
      request_id: randomUUID(),
      rows: preview.rows.map(({target_type, display_name, phone, email}) =>
        ({target_type, display_name, phone, email})),
      actions: ["create", "skip"],
    };
    const confirm = await postJson(baseUrl, confirmBody);
    assert.equal(confirm.status, 200);
    const confirmedBody = await confirm.json() as {
      receipt: {
        outcome: string;
        created_count: number;
        created_targets: Array<{row_number: number; target_id: string}>;
      };
    };
    assert.equal(confirmedBody.receipt.outcome, "confirmed");
    assert.equal(confirmedBody.receipt.created_count, 1);
    assert.equal(confirmedBody.receipt.created_targets.length, 1);
    assert.equal(confirmedBody.receipt.created_targets[0]?.row_number, 1);
    const targetId = confirmedBody.receipt.created_targets[0]?.target_id;
    assert.ok(targetId);

    const replay = await postJson(baseUrl, confirmBody);
    assert.equal(replay.status, 200);
    assert.deepEqual(await replay.json(), confirmedBody);

    await client.query("SAVEPOINT csv_import_drift");
    const drift = await postJson(baseUrl, {
      ...confirmBody,
      actions: ["skip", "create"],
    });
    assert.equal(drift.status, 409);
    await client.query("ROLLBACK TO SAVEPOINT csv_import_drift");
    await client.query("RELEASE SAVEPOINT csv_import_drift");

    await client.query("RESET ROLE");
    const targetRows = await client.query(
      `SELECT row_to_json(target_row)::text AS value
         FROM app_data.promotion_targets AS target_row
        WHERE promotion_target_id = $1::uuid
          AND workspace_id = $2::uuid`,
      [targetId, context.current.workspace.id],
    );
    assert.equal(targetRows.rowCount, 1);
    const createdTargetCount = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.promotion_targets
        WHERE created_by_app_user_id = $1::uuid`,
      [context.appUserId],
    );
    assert.equal(createdTargetCount.rows[0]?.count, 1);
    const assignments = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.promotion_target_assignments
        WHERE promotion_target_id = $1::uuid
          AND app_user_id = $2::uuid
          AND ended_at IS NULL`,
      [targetId, context.appUserId],
    );
    assert.equal(assignments.rows[0]?.count, 1);
    const createdEvents = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.promotion_target_access_events
        WHERE promotion_target_id = $1::uuid AND action = 'created'`,
      [targetId],
    );
    assert.equal(createdEvents.rows[0]?.count, 1);

    const projectRelations = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.promotion_target_project_relationships
        WHERE promotion_target_id = $1::uuid`,
      [targetId],
    );
    const contactLinks = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.contact_target_links
        WHERE promotion_target_id = $1::uuid`,
      [targetId],
    );
    const institutionRelations = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.promotion_target_institution_relationships
        WHERE person_target_id = $1::uuid
           OR institution_target_id = $1::uuid`,
      [targetId],
    );
    const contacts = await client.query(
      `SELECT count(*)::int AS count
         FROM app_data.contacts
        WHERE app_user_id = $1::uuid AND workspace_id = $2::uuid`,
      [context.appUserId, context.current.workspace.id],
    );
    assert.equal(projectRelations.rows[0]?.count, 0);
    assert.equal(contactLinks.rows[0]?.count, 0);
    assert.equal(institutionRelations.rows[0]?.count, 0);
    assert.equal(contacts.rows[0]?.count, 0);

    const previewRows = await client.query(
      `SELECT row_to_json(record_row)::text AS value
         FROM app_private.personal_target_csv_import_previews AS record_row
        WHERE preview_id = $1::uuid`,
      [preview.receipt.preview_id],
    );
    const claimRows = await client.query(
      `SELECT row_to_json(record_row)::text AS value
         FROM app_private.personal_target_csv_import_request_claims AS record_row
        WHERE preview_id = $1::uuid AND request_id = $2::uuid
          AND outcome = 'confirmed'`,
      [preview.receipt.preview_id, confirmBody.request_id],
    );
    const auditRows = await client.query(
      `SELECT row_to_json(record_row)::text AS value
         FROM app_private.personal_target_csv_import_audit_events AS record_row
        WHERE preview_id = $1::uuid`,
      [preview.receipt.preview_id],
    );
    const auditPhases = await client.query(
      `SELECT count(*) FILTER (
                 WHERE phase = 'preview' AND outcome = 'previewed'
               )::int AS preview_count,
               count(*) FILTER (
                 WHERE phase = 'confirm' AND request_id = $2::uuid
                   AND outcome = 'confirmed'
               )::int AS confirm_count
         FROM app_private.personal_target_csv_import_audit_events
        WHERE preview_id = $1::uuid`,
      [preview.receipt.preview_id, confirmBody.request_id],
    );
    assert.equal(previewRows.rowCount, 1);
    assert.equal(claimRows.rowCount, 1);
    assert.ok((auditRows.rowCount ?? 0) >= 2);
    assert.equal(auditPhases.rows[0]?.preview_count, 1);
    assert.equal(auditPhases.rows[0]?.confirm_count, 1);
    assert.ok(auditRows.rows.some((row) =>
      String(row.value).includes(String(confirmBody.request_id))));
    const privateValues = [
      ...previewRows.rows,
      ...claimRows.rows,
      ...auditRows.rows,
    ].map((row) => String(row.value));
    for (const privateValue of privateValues) {
      assert.doesNotMatch(privateValue, /CSV Import Created|CSV Import Skipped|312-555-0191|312-555-0192|created@example\.test|skipped@example\.test/);
    }

    process.stdout.write("Personal target CSV import HTTP integration: passed\n");
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

async function listen(server: ReturnType<typeof createBackendServer>): Promise<{port: number}> {
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  return {port: address.port};
}

async function close(server: ReturnType<typeof createBackendServer>): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}

async function postJson(baseUrl: string, body: unknown): Promise<Response> {
  return fetch(`${baseUrl}/v1/promotion-targets/imports/csv/confirm`, {
    method: "POST",
    headers: {
      authorization: "Bearer synthetic-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}
