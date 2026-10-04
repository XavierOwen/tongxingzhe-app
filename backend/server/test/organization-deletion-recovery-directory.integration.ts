import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";
import test from "node:test";

import {
  OrganizationDeletionRecoveryDirectoryStoreError,
  PostgresOrganizationDeletionRecoveryDirectoryStore,
} from "../src/organization-deletion-recovery-directory.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for organization deletion recovery directory integration");
}
const fixturePath = process.env.ORGANIZATION_DELETION_RECOVERY_DIRECTORY_FIXTURE ??
  resolve(dirname(fileURLToPath(import.meta.url)),
    "../../../database/fixtures/0101_organization_deletion_recovery_directory.sql");
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*$/gmu, "")
  .replace(/^COMMIT;\s*$/gmu, "")
  .replace(/^ROLLBACK;\s*$/gmu, "")
  .replace(
    "UPDATE app_data.organization_owner_assignments AS assignment",
    "INSERT INTO app_data.organization_memberships(organization_membership_id, organization_workspace_id, app_user_id, active_from_utc) " +
      "SELECT gen_random_uuid(), org.workspace_id, user_row.user_id, clock.now_utc - interval '1 hour' " +
      "FROM fixture_0101_orgs AS org CROSS JOIN fixture_0101_users AS user_row CROSS JOIN fixture_0101_clock AS clock " +
      "WHERE org.n = 1 AND user_row.n = 3;\n" +
      "UPDATE app_data.organization_owner_assignments AS assignment",
  );

test("0101 runtime bridge returns only recoverable current-owner directory rows without lifecycle writes",
  async () => {
    const pool = new Pool({ connectionString: databaseUrl });
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(fixture);
      const issuerResult = await client.query(
        "SELECT issuer FROM fixture_0101_clock",
      );
      const issuer = issuerResult.rows[0]?.issuer as string | undefined;
      assert.ok(issuer);
      const lifecycleCounts = async () => {
        const result = await client.query(
          "SELECT (SELECT count(*) FROM app_private.organization_deletion_current) AS attempts, " +
            "(SELECT count(*) FROM app_private.organization_deletion_request_claims) AS deletion_claims, " +
            "(SELECT count(*) FROM app_private.organization_deletion_restore_claims) AS restore_claims, " +
            "(SELECT count(*) FROM app_private.organization_deletion_audit_events) AS audit_events",
        );
        return result.rows[0];
      };
      const before = await lifecycleCounts();

      await client.query("SET LOCAL ROLE tongxingzhe_runtime");
      const store = new PostgresOrganizationDeletionRecoveryDirectoryStore(
        async (text, values) => client.query(text, [...values]),
      );
      const ownerItems = await store.list({ issuer, subject: " owner exact " });
      assert.deepEqual(ownerItems.map((item) => item.displayName), ["Alpha", "Beta"]);
      assert.equal(ownerItems.length, 2);
      for (const item of ownerItems) {
        assert.equal(item.status, "deletion_pending");
        assert.equal(
          Date.parse(item.observedAtUtc) >= Date.parse(item.effectiveAtUtc) &&
            Date.parse(item.observedAtUtc) < Date.parse(item.purgeAfterUtc),
          true,
        );
        assert.equal(Date.parse(item.purgeAfterUtc) - Date.parse(item.effectiveAtUtc),
          720 * 60 * 60 * 1000);
      }
      assert.deepEqual(await store.list({ issuer, subject: "empty" }), []);
      await assertStoreError(client,
        () => store.list({ issuer, subject: "inactive" }),
        "organization_deletion_recovery_directory_forbidden",
      );
      await assertStoreError(client,
        () => store.list({ issuer, subject: "unknown" }),
        "organization_deletion_recovery_directory_forbidden",
      );
      await client.query("RESET ROLE");
      assert.deepEqual(await lifecycleCounts(), before);
    } finally {
      try {
        await client.query("ROLLBACK");
      } finally {
        client.release();
        await pool.end();
      }
    }
  });

async function assertStoreError(
  client: { query(text: string): Promise<unknown> },
  operation: () => Promise<unknown>,
  code: "organization_deletion_recovery_directory_forbidden",
): Promise<void> {
  await client.query("SAVEPOINT recovery_directory_forbidden");
  try {
    await assert.rejects(operation, (error: unknown) => {
      assert.ok(error instanceof OrganizationDeletionRecoveryDirectoryStoreError);
      assert.equal(error.code, code);
      assert.equal(error.message, code);
      return true;
    });
  } finally {
    await client.query("ROLLBACK TO SAVEPOINT recovery_directory_forbidden");
    await client.query("RELEASE SAVEPOINT recovery_directory_forbidden");
  }
}
