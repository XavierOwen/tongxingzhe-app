import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {Pool} from "pg";
import test from "node:test";

import {
  OrganizationDirectedAccountInvitationStoreError,
  PostgresOrganizationDirectedAccountInvitationStore,
  type OrganizationDirectedAccountInvitationAcceptResult,
  type OrganizationDirectedAccountInvitationCreateResult,
} from "../src/organization-directed-account-invitations.js";

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for invitation integration");
}

const fixturePath =
  process.env.ORGANIZATION_DIRECTED_ACCOUNT_INVITATION_FIXTURE ?? resolve(
    dirname(fileURLToPath(import.meta.url)),
    "../../../database/fixtures/0087_organization_directed_account_invitation.sql",
  );
const fixture = readFileSync(fixturePath, "utf8")
  .replace(/^\\set ON_ERROR_STOP on\s*/mu, "")
  .replace(/^BEGIN;\s*/mu, "")
  .replace(/^ROLLBACK;\s*$/mu, "");

const issuer = "https://synthetic-8701.example/auth/v1";
const ownerIdentity = {issuer, subject: "main-owner"};
const targetIdentity = {issuer, subject: "expired-target"};
const nonOwnerIdentity = {issuer, subject: "main-non-owner"};
const invitationId = "00000000-8701-3900-0000-000000000001";
const unknownInvitationId = "00000000-8701-3900-0000-000000009999";
const organizationWorkspaceId = "00000000-8701-2000-0000-000000000001";
const targetAppUserId = "00000000-8701-0000-0000-000000000011";
const driftTargetAppUserId = "00000000-8701-0000-0000-000000000004";

test("invitation runtime bridges create, accept, and replay exact receipts", async () => {
  const pool = new Pool({connectionString: databaseUrl});
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(fixture);
    await client.query("SET LOCAL ROLE tongxingzhe_runtime");

    const query = async (text: string, values: readonly unknown[]) =>
      client.query(text, [...values]);
    const store = new PostgresOrganizationDirectedAccountInvitationStore(query);

    const created = await store.create(
      ownerIdentity,
      invitationId,
      organizationWorkspaceId,
      targetAppUserId,
    );
    const accepted = await store.accept(targetIdentity, invitationId);
    const createReplay = await store.create(
      ownerIdentity,
      invitationId,
      organizationWorkspaceId,
      targetAppUserId,
    );
    const acceptReplay = await store.accept(targetIdentity, invitationId);

    assert.deepEqual(createReplay, created);
    assert.deepEqual(acceptReplay, accepted);
    assertCreateReceipt(created);
    assertAcceptReceipt(accepted);
    assert.equal(created.invitationId, invitationId);
    assert.equal(accepted.invitationId, invitationId);
    assert.equal(created.organizationWorkspaceId, organizationWorkspaceId);
    assert.equal(accepted.organizationWorkspaceId, organizationWorkspaceId);
    assert.equal(
      Date.parse(created.expiresAtUtc) - Date.parse(created.issuedAtUtc),
      168 * 60 * 60 * 1000,
    );

    await client.query("SAVEPOINT forbidden_case");
    await assertStoreError(
      () => store.accept(nonOwnerIdentity, unknownInvitationId),
      "organization_invitation_forbidden",
    );
    await client.query("ROLLBACK TO SAVEPOINT forbidden_case");
    await client.query("RELEASE SAVEPOINT forbidden_case");

    await client.query("SAVEPOINT conflict_case");
    await assertStoreError(
      () => store.create(
        ownerIdentity,
        invitationId,
        organizationWorkspaceId,
        driftTargetAppUserId,
      ),
      "organization_invitation_conflict",
    );
    await client.query("ROLLBACK TO SAVEPOINT conflict_case");
    await client.query("RELEASE SAVEPOINT conflict_case");

    process.stdout.write(
      "Backend organization invitation runtime integration: passed\n",
    );
  } finally {
    try {
      await client.query("ROLLBACK");
    } finally {
      client.release();
      await pool.end();
    }
  }
});

function assertCreateReceipt(
  result: OrganizationDirectedAccountInvitationCreateResult,
): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "expiresAtUtc",
    "invitationId",
    "issuedAtUtc",
    "organizationInvitationContractId",
    "organizationWorkspaceId",
  ]);
  assert.equal(
    result.organizationInvitationContractId,
    "organization-directed-account-invitation:v1",
  );
  assertUuid(result.invitationId);
  assertUuid(result.organizationWorkspaceId);
  assertUtcInstant(result.issuedAtUtc);
  assertUtcInstant(result.expiresAtUtc);
}

function assertAcceptReceipt(
  result: OrganizationDirectedAccountInvitationAcceptResult,
): void {
  assert.deepEqual(Object.keys(result).sort(), [
    "acceptedAtUtc",
    "invitationId",
    "organizationInvitationContractId",
    "organizationMembershipId",
    "organizationWorkspaceId",
  ]);
  assert.equal(
    result.organizationInvitationContractId,
    "organization-directed-account-invitation:v1",
  );
  assertUuid(result.invitationId);
  assertUuid(result.organizationWorkspaceId);
  assertUuid(result.organizationMembershipId);
  assertUtcInstant(result.acceptedAtUtc);
}

function assertUuid(value: string): void {
  assert.match(
    value,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  );
}

function assertUtcInstant(value: string): void {
  assert.match(value, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
}

async function assertStoreError(
  operation: () => Promise<unknown>,
  code:
    | "organization_invitation_forbidden"
    | "organization_invitation_conflict",
): Promise<void> {
  await assert.rejects(operation, (error: unknown) => {
    assert.ok(error instanceof OrganizationDirectedAccountInvitationStoreError);
    assert.equal(error.code, code);
    assert.equal(error.message, code);
    return true;
  });
}
