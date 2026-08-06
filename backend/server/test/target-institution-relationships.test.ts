import assert from "node:assert/strict";
import test from "node:test";

import {
  createTargetInstitutionRelationship,
  endTargetInstitutionRelationship,
  listTargetInstitutionRelationships,
  PostgresTargetInstitutionRelationshipStore,
  TargetInstitutionRelationshipStoreError,
  type CreateTargetInstitutionRelationshipInput,
  type EndTargetInstitutionRelationshipInput,
  type TargetInstitutionRelationship,
  type TargetInstitutionRelationshipMutation,
  type TargetInstitutionRelationshipStore,
} from "../src/target-institution-relationships.js";
import type {SessionContext} from "../src/session-context.js";

const relationship: TargetInstitutionRelationship = {
  id: "77777777-7777-4777-8777-777777777777",
  personTargetId: "44444444-4444-4444-8444-444444444444",
  institutionTargetId: "55555555-5555-4555-8555-555555555555",
  kind: "employment_representative",
  roleDescription: "项目协调员",
  startedAt: "2026-08-06T12:00:00.000Z",
  endedAt: null,
  status: "active",
  revisionNumber: 1,
  history: [{
    revisionNumber: 1,
    eventType: "created",
    oldStatus: null,
    newStatus: "active",
    endedAt: null,
    changedByAppUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    changedAt: "2026-08-06T12:00:00.000Z",
  }],
};

test("relationship reads need target access and writes need a separate capability", async () => {
  const store = new MemoryStore();

  const listed = await listTargetInstitutionRelationships(
    "Bearer token",
    dependencies(store, ["view_assigned_target_pii"]),
  );
  const denied = await createTargetInstitutionRelationship(
    "Bearer token",
    createBody(),
    dependencies(store, ["view_assigned_target_pii"]),
  );

  assert.equal(listed.status, 200);
  assert.deepEqual(denied, {
    status: 403,
    body: {error: {code: "capability_forbidden"}},
  });
  assert.equal(store.listCalls, 1);
  assert.equal(store.createCalls, 0);
});

test("create accepts only explicit person, institution, kind, role, and mutation", async () => {
  const store = new MemoryStore();
  const result = await createTargetInstitutionRelationship(
    "Bearer token",
    createBody(),
    dependencies(store, [
      "view_assigned_target_pii",
      "manage_assigned_target_relations",
    ]),
  );

  assert.equal(result.status, 201);
  assert.deepEqual(store.createInput, {
    personTargetId: relationship.personTargetId,
    institutionTargetId: relationship.institutionTargetId,
    kind: "employment_representative",
    roleDescription: "项目协调员",
    mutationId: "institution-relation-create-1",
  });

  const forged = await createTargetInstitutionRelationship(
    "Bearer token",
    {...createBody(), workspace_id: "forged"},
    dependencies(store, [
      "view_assigned_target_pii",
      "manage_assigned_target_relations",
    ]),
  );
  assert.equal(forged.status, 400);
  assert.equal(store.createCalls, 1);
});

test("other kind requires a role description before store access", async () => {
  const store = new MemoryStore();
  const result = await createTargetInstitutionRelationship(
    "Bearer token",
    {...createBody(), relationship_kind: "other", role_description: null},
    dependencies(store, [
      "view_assigned_target_pii",
      "manage_assigned_target_relations",
    ]),
  );

  assert.deepEqual(result, {
    status: 400,
    body: {error: {code: "invalid_target_institution_relationship"}},
  });
  assert.equal(store.createCalls, 0);
});

test("ending uses the visible revision and maps a concurrent winner to 409", async () => {
  const store = new MemoryStore();
  store.endError = new TargetInstitutionRelationshipStoreError("conflict");
  const result = await endTargetInstitutionRelationship(
    "Bearer token",
    relationship.id,
    {expected_revision: 1, mutation_id: "institution-relation-end-1"},
    dependencies(store, [
      "view_assigned_target_pii",
      "manage_assigned_target_relations",
    ]),
  );

  assert.deepEqual(result, {
    status: 409,
    body: {error: {code: "target_institution_relationship_conflict"}},
  });
  assert.deepEqual(store.endInput, {
    expectedRevision: 1,
    mutationId: "institution-relation-end-1",
  });
});

test("Postgres adapter passes trusted scope and parses append-only history", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresTargetInstitutionRelationshipStore(
    async (text, values) => {
      calls.push({text, values});
      return text.includes("list_assigned")
        ? {rows: [{relationship: relationshipDocument()}]}
        : {rows: [{result: {
            duplicate: false,
            relationship: relationshipDocument(),
          }}]};
    },
  );
  const trustedContext = context([]);

  const listed = await store.list(trustedContext);
  const created = await store.create(trustedContext, {
    personTargetId: relationship.personTargetId,
    institutionTargetId: relationship.institutionTargetId,
    kind: relationship.kind,
    roleDescription: relationship.roleDescription,
    mutationId: "institution-relation-create-1",
  });
  const ended = await store.end(trustedContext, relationship.id, {
    expectedRevision: 1,
    mutationId: "institution-relation-end-1",
  });

  assert.deepEqual(listed, [relationship]);
  assert.deepEqual(created.relationship, relationship);
  assert.deepEqual(ended.relationship, relationship);
  assert.deepEqual(calls[1]?.values, [
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    "22222222-2222-4222-8222-222222222222",
    relationship.personTargetId,
    relationship.institutionTargetId,
    relationship.kind,
    relationship.roleDescription,
    "institution-relation-create-1",
  ]);
  assert.deepEqual(calls[2]?.values.slice(3), [
    relationship.id,
    1,
    "institution-relation-end-1",
  ]);
});

function createBody() {
  return {
    person_target_id: relationship.personTargetId,
    institution_target_id: relationship.institutionTargetId,
    relationship_kind: relationship.kind,
    role_description: "  项目协调员  ",
    mutation_id: "institution-relation-create-1",
  };
}

function relationshipDocument() {
  return {
    relationship_id: relationship.id,
    person_target_id: relationship.personTargetId,
    institution_target_id: relationship.institutionTargetId,
    relationship_kind: relationship.kind,
    role_description: relationship.roleDescription,
    started_at: relationship.startedAt,
    ended_at: relationship.endedAt,
    status: relationship.status,
    revision_number: relationship.revisionNumber,
    history: relationship.history.map((revision) => ({
      revision_number: revision.revisionNumber,
      event_type: revision.eventType,
      old_status: revision.oldStatus,
      new_status: revision.newStatus,
      ended_at: revision.endedAt,
      changed_by_app_user_id: revision.changedByAppUserId,
      changed_at: revision.changedAt,
    })),
  };
}

function dependencies(
  relationshipStore: TargetInstitutionRelationshipStore,
  capabilities: readonly string[],
) {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => context(capabilities),
    },
    relationshipStore,
  };
}

function context(capabilities: readonly string[]): SessionContext {
  return {
    appUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    current: {
      workspace: {
        id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        kind: "personal",
        name: "个人空间",
      },
      project: {
        id: "22222222-2222-4222-8222-222222222222",
        name: "校园推广",
      },
      questionnaireVersion: {
        id: "11111111-1111-4111-8111-111111111111",
        versionNumber: 1,
      },
    },
    capabilities,
  };
}

class MemoryStore implements TargetInstitutionRelationshipStore {
  listCalls = 0;
  createCalls = 0;
  createInput: CreateTargetInstitutionRelationshipInput | null = null;
  endInput: EndTargetInstitutionRelationshipInput | null = null;
  endError: unknown;

  async list(): Promise<readonly TargetInstitutionRelationship[]> {
    this.listCalls += 1;
    return [relationship];
  }

  async create(
    _context: SessionContext,
    input: CreateTargetInstitutionRelationshipInput,
  ): Promise<TargetInstitutionRelationshipMutation> {
    this.createCalls += 1;
    this.createInput = input;
    return {duplicate: false, relationship};
  }

  async end(
    _context: SessionContext,
    _relationshipId: string,
    input: EndTargetInstitutionRelationshipInput,
  ): Promise<TargetInstitutionRelationshipMutation> {
    this.endInput = input;
    if (this.endError !== undefined) throw this.endError;
    return {duplicate: false, relationship};
  }
}
