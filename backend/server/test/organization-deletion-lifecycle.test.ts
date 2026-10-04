import assert from "node:assert/strict";
import test from "node:test";
import {
  handleOrganizationDeletionLifecycle,
  matchOrganizationDeletionLifecycleRequestTarget,
  OrganizationDeletionLifecycleStoreError,
  parseOrganizationDeletionLifecycleBody,
  PostgresOrganizationDeletionLifecycleStore,
  type OrganizationDeletionLifecycleRequest,
} from "../src/organization-deletion-lifecycle.js";
import {
  IdentityVerificationError,
  type VerifiedIdentity,
} from "../src/identity.js";

const requestId = "123e4567-e89b-12d3-a456-426614174000";
const workspaceId = "123e4567-e89b-12d3-a456-426614174001";
const deletionRequestId = "123e4567-e89b-12d3-a456-426614174002";
const identity: VerifiedIdentity = {
  issuer: "https://issuer.example",
  subject: "subject-123",
};
const deletionReceipt = {
  organizationDeletionContractId: "organization-deletion-request:v1" as const,
  organizationWorkspaceId: workspaceId,
  deletionRequestId,
  effectiveAtUtc: "2030-01-01T00:00:00.123456Z",
  purgeAfterUtc: "2030-01-31T00:00:00.123456Z",
};
const restorationReceipt = {
  organizationDeletionRestoreContractId: "organization-deletion-restore:v1" as const,
  organizationWorkspaceId: workspaceId,
  deletionRequestId,
  restoredAtUtc: "2030-01-02T03:04:05.123456Z",
};

function request(
  operation: "request" | "restore",
  body: unknown,
  overrides: Partial<OrganizationDeletionLifecycleRequest> = {},
): OrganizationDeletionLifecycleRequest {
  return {
    authorization: "Bearer token",
    workspaceId,
    hasQuery: false,
    operation,
    readBody: async () => body,
    ...overrides,
  };
}

test("raw lifecycle matcher preserves query presence and rejects aliases", () => {
  assert.deepEqual(
    matchOrganizationDeletionLifecycleRequestTarget(
      `/v1/organizations/${workspaceId}/deletion-requests?`,
    ),
    {workspaceId, hasQuery: true, operation: "request"},
  );
  assert.deepEqual(
    matchOrganizationDeletionLifecycleRequestTarget(
      `/v1/organizations/${workspaceId}/restorations`,
    ),
    {workspaceId, hasQuery: false, operation: "restore"},
  );
  for (const path of [
    `/v1/organizations/${workspaceId}/deletion-requests/`,
    `/v1/organizations/${workspaceId}%2F/deletion-requests`,
    `/v1/organizations/%31${workspaceId.slice(1)}/restorations`,
    "/v1/organizations/./restorations",
    "/v1/organizations/../deletion-requests",
    `/v1/organizations//restorations`,
  ]) {
    assert.equal(matchOrganizationDeletionLifecycleRequestTarget(path), null);
  }
});

test("lifecycle request bodies accept only the exact operation keys and UUIDs", () => {
  assert.deepEqual(
    parseOrganizationDeletionLifecycleBody("request", {
      request_id: requestId.toUpperCase(),
    }),
    {requestId},
  );
  assert.deepEqual(
    parseOrganizationDeletionLifecycleBody("restore", {
      request_id: requestId,
      deletion_request_id: deletionRequestId,
    }),
    {requestId, deletionRequestId},
  );
  for (const invalid of [
    null,
    [],
    {},
    {request_id: requestId, extra: true},
    {request_id: "not-a-uuid"},
  ]) {
    assert.equal(parseOrganizationDeletionLifecycleBody("request", invalid), null);
  }
  for (const invalid of [
    {request_id: requestId},
    {request_id: requestId, deletion_request_id: deletionRequestId, extra: true},
    {request_id: requestId, deletion_request_id: "not-a-uuid"},
  ]) {
    assert.equal(parseOrganizationDeletionLifecycleBody("restore", invalid), null);
  }
});

test("identity is verified before query, path, and body shape", async () => {
  const events: string[] = [];
  const handler = (overrides: Partial<OrganizationDeletionLifecycleRequest>) =>
    handleOrganizationDeletionLifecycle(
      request("request", {request_id: requestId}, {
        readBody: async () => {
          events.push("body");
          return {request_id: requestId};
        },
        ...overrides,
      }),
      {
        identityVerifier: {
          verify: async () => {
            events.push("identity");
            return identity;
          },
        },
        store: {
          requestDeletion: async () => {
            events.push("store");
            return deletionReceipt;
          },
          restore: async () => restorationReceipt,
        },
      },
    );

  const invalidQuery = await handler({hasQuery: true});
  assert.deepEqual(invalidQuery, {
    status: 400,
    body: {error: {code: "invalid_organization_deletion_request"}},
  });
  assert.deepEqual(events, ["identity"]);
  events.length = 0;

  const invalidPath = await handler({workspaceId: "bad"});
  assert.equal(invalidPath.status, 400);
  assert.deepEqual(events, ["identity"]);
  events.length = 0;

  const unauthenticated = await handleOrganizationDeletionLifecycle(
    request("request", null, {authorization: "Bearer bad"}),
    {
      identityVerifier: {
        verify: async () => {
          throw new IdentityVerificationError("unauthenticated");
        },
      },
      store: undefined,
    },
  );
  assert.deepEqual(unauthenticated, {
    status: 401,
    body: {error: {code: "unauthenticated"}},
  });
});

test("request and restoration return the fixed typed receipts", async () => {
  const store = {
    requestDeletion: async (...args: readonly unknown[]) => {
      assert.deepEqual(args, [identity, requestId, workspaceId]);
      return deletionReceipt;
    },
    restore: async (...args: readonly unknown[]) => {
      assert.deepEqual(args, [identity, requestId, workspaceId, deletionRequestId]);
      return restorationReceipt;
    },
  };
  const dependencies = {
    identityVerifier: {verify: async () => identity},
    store,
  };
  const requestResult = await handleOrganizationDeletionLifecycle(
    request("request", {request_id: requestId}),
    dependencies,
  );
  assert.deepEqual(requestResult, {
    status: 200,
    body: {
      organization_deletion_contract_id: "organization-deletion-request:v1",
      organization_workspace_id: workspaceId,
      deletion_request_id: deletionRequestId,
      effective_at_utc: deletionReceipt.effectiveAtUtc,
      purge_after_utc: deletionReceipt.purgeAfterUtc,
    },
  });
  const restoreResult = await handleOrganizationDeletionLifecycle(
    request("restore", {
      request_id: requestId,
      deletion_request_id: deletionRequestId,
    }),
    dependencies,
  );
  assert.deepEqual(restoreResult, {
    status: 200,
    body: {
      organization_deletion_restore_contract_id:
        "organization-deletion-restore:v1",
      organization_workspace_id: workspaceId,
      deletion_request_id: deletionRequestId,
      restored_at_utc: restorationReceipt.restoredAtUtc,
    },
  });
});

test("adapter calls only identity bridges and preserves six timestamp digits", async () => {
  const calls: {text: string; values: readonly unknown[]}[] = [];
  const store = new PostgresOrganizationDeletionLifecycleStore(async (text, values) => {
    calls.push({text, values});
    return {
      rows: text.includes("request_organization_deletion_for_identity_v1")
        ? [{
          organization_deletion_contract_id: "organization-deletion-request:v1",
          organization_workspace_id: workspaceId,
          deletion_request_id: requestId,
          effective_at_utc: "2030-01-01T00:00:00.123456Z",
          purge_after_utc: "2030-01-31T00:00:00.123456Z",
        }]
        : [{
          organization_deletion_restore_contract_id: "organization-deletion-restore:v1",
          organization_workspace_id: workspaceId,
          deletion_request_id: deletionRequestId,
          restored_at_utc: "2030-01-02T03:04:05.123456Z",
        }],
    };
  });

  const deletion = await store.requestDeletion(identity, requestId, workspaceId);
  const restoration = await store.restore(
    identity,
    requestId,
    workspaceId,
    deletionRequestId,
  );
  assert.equal(deletion.effectiveAtUtc, "2030-01-01T00:00:00.123456Z");
  assert.equal(deletion.purgeAfterUtc, "2030-01-31T00:00:00.123456Z");
  assert.equal(restoration.restoredAtUtc, "2030-01-02T03:04:05.123456Z");
  assert.match(calls[0]!.text, /app_data\.request_organization_deletion_for_identity_v1/);
  assert.match(calls[0]!.text, /to_char\(effective_at_utc AT TIME ZONE 'UTC'/);
  assert.match(calls[0]!.text, /to_char\(purge_after_utc AT TIME ZONE 'UTC'/);
  assert.match(calls[1]!.text, /app_data\.restore_organization_for_identity_v1/);
  assert.match(calls[1]!.text, /to_char\(restored_at_utc AT TIME ZONE 'UTC'/);
  assert.doesNotMatch(calls.map((call) => call.text).join("\n"), /app_private\./);
  assert.deepEqual(calls[0]!.values, [identity.issuer, identity.subject, requestId, workspaceId]);
  assert.deepEqual(calls[1]!.values, [identity.issuer, identity.subject, requestId, workspaceId, deletionRequestId]);
});

test("known lifecycle SQL failures map narrowly; malformed rows and unknown errors fail closed", async () => {
  const cases = [
    ["22023", "invalid organization deletion request", "invalid_organization_deletion_request", 400],
    ["42501", "organization deletion forbidden", "organization_deletion_forbidden", 403],
    ["22023", "organization deletion idempotency conflict", "organization_deletion_conflict", 409],
    ["22023", "invalid organization deletion request identity", "organization_deletion_unavailable", 503],
    ["55000", "organization deletion unavailable", "organization_deletion_unavailable", 503],
    ["22023", "invalid organization restoration request", "invalid_organization_restoration_request", 400],
    ["42501", "organization restoration forbidden", "organization_restoration_forbidden", 403],
    ["22023", "organization restoration idempotency conflict", "organization_restoration_conflict", 409],
    ["XX000", "private detail", "organization_restoration_unavailable", 503],
  ] as const;

  for (const [sqlstate, message, code, status] of cases) {
    const operation = code.includes("restoration") ? "restore" : "request";
    const store = new PostgresOrganizationDeletionLifecycleStore(async () => {
      throw Object.assign(new Error(message), {code: sqlstate});
    });
    let error!: OrganizationDeletionLifecycleStoreError;
    await assert.rejects(
      operation === "request"
        ? store.requestDeletion(identity, requestId, workspaceId)
        : store.restore(identity, requestId, workspaceId, deletionRequestId),
      (caught: unknown) => {
        assert.ok(caught instanceof OrganizationDeletionLifecycleStoreError);
        error = caught;
        return true;
      },
    );
    assert.equal(error.code, code);
    const result = await handleOrganizationDeletionLifecycle(
      request(operation, operation === "request"
        ? {request_id: requestId}
        : {request_id: requestId, deletion_request_id: deletionRequestId}),
      {
        identityVerifier: {verify: async () => identity},
        store: {
          requestDeletion: async () => { throw error; },
          restore: async () => { throw error; },
        },
      },
    );
    assert.deepEqual(result, {status, body: {error: {code}}});
    assert.equal(JSON.stringify(result).includes("private detail"), false);
  }

  const malformed = new PostgresOrganizationDeletionLifecycleStore(async () => ({
    rows: [{
      organization_deletion_contract_id: "organization-deletion-request:v1",
      organization_workspace_id: workspaceId,
      deletion_request_id: deletionRequestId,
      effective_at_utc: new Date("2030-01-01T00:00:00.123Z"),
      purge_after_utc: "2030-01-31T00:00:00.123456Z",
    }],
  }));
  await assert.rejects(
    malformed.requestDeletion(identity, requestId, workspaceId),
    (error: unknown) => error instanceof OrganizationDeletionLifecycleStoreError &&
      error.code === "organization_deletion_unavailable",
  );
});
