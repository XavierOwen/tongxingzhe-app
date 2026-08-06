import assert from "node:assert/strict";
import test from "node:test";

import {
  configurePromotionTargetStageAliases,
  createPromotionTarget,
  listAssignedPromotionTargets,
  PostgresPromotionTargetStore,
  updatePromotionTargetRelationship,
  type CreatePromotionTargetInput,
  type PromotionTargetProfile,
  type PromotionTargetRelationship,
  type PromotionTargetRelationshipUpdate,
  type PromotionTargetStageAlias,
  type PromotionTargetStageAliasInput,
  type PromotionTargetStore,
  type UpdatePromotionTargetRelationshipInput,
} from "../src/promotion-targets.js";
import type {SessionContext} from "../src/session-context.js";

const profile: PromotionTargetProfile = {
  id: "44444444-4444-4444-8444-444444444444",
  type: "person",
  displayName: "王小明",
  phone: "+1 312 555 0100",
  email: null,
  createdAt: "2026-08-06T12:00:00.000Z",
  hasCurrentProjectRelationship: false,
  projectRelationship: null,
};

const aliases: readonly PromotionTargetStageAlias[] = Array.from(
  {length: 5},
  (_, stage) => ({
    stage,
    displayStage: stage * 2,
    displayName: stage === 3 ? "明确推进" : null,
  }),
);

const relationship: PromotionTargetRelationship = {
  targetId: profile.id,
  projectId: "22222222-2222-4222-8222-222222222222",
  stage: 3,
  displayStage: 6,
  lifecycleStatus: "active",
  followUpNote: "下周再次联系",
  revisionNumber: 2,
  updatedAt: "2026-08-06T13:00:00.000Z",
  stageAliases: aliases,
  history: [{
    revisionNumber: 2,
    oldStage: 2,
    newStage: 3,
    oldLifecycleStatus: "active",
    newLifecycleStatus: "active",
    followUpNote: "下周再次联系",
    changedFields: ["stage", "follow_up_note"],
    reasonCode: "progress_update",
    reasonDetail: null,
    changedByAppUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    changedAt: "2026-08-06T13:00:00.000Z",
  }],
};

test("target operations recheck capabilities before reading PII", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, ["record_contact"]);

  const [listed, created] = await Promise.all([
    listAssignedPromotionTargets("Bearer token", deps),
    createPromotionTarget("Bearer token", validBody(), deps),
  ]);

  for (const result of [listed, created]) {
    assert.deepEqual(result, {
      status: 403,
      body: {error: {code: "capability_forbidden"}},
    });
  }
  assert.equal(store.calls, 0);
});

test("create accepts explicit profile fields and never trusts workspace input", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, [
    "create_target",
    "view_assigned_target_pii",
  ]);

  const created = await createPromotionTarget(
    "Bearer token",
    validBody(),
    deps,
  );
  assert.equal(created.status, 201);
  assert.deepEqual(store.created, {
    type: "person",
    displayName: "王小明",
    phone: "+1 312 555 0100",
    email: null,
    requestId: "create-target-1",
  });

  const forged = await createPromotionTarget(
    "Bearer token",
    {...validBody(), workspace_id: "forged-workspace"},
    deps,
  );
  assert.deepEqual(forged, {
    status: 400,
    body: {error: {code: "invalid_promotion_target"}},
  });
  assert.equal(store.calls, 1);
});

test("create rejects missing, blank, or unexpected profile fields", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, [
    "create_target",
    "view_assigned_target_pii",
  ]);
  const invalidBodies = [
    {},
    {...validBody(), display_name: "   "},
    {...validBody(), phone: ""},
    {...validBody(), target_type: "group"},
  ];

  for (const body of invalidBodies) {
    const result = await createPromotionTarget("Bearer token", body, deps);
    assert.equal(result.status, 400);
  }
  assert.equal(store.calls, 0);
});

test("Postgres adapter passes only the trusted context and request document", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresPromotionTargetStore(async (text, values) => {
    calls.push({text, values});
    return {rows: [{target: {
      target_id: profile.id,
      target_type: profile.type,
      display_name: profile.displayName,
      phone: profile.phone,
      email: profile.email,
      created_at: profile.createdAt,
    }}]};
  });

  const created = await store.create(context([]), {
    type: "person",
    displayName: "王小明",
    phone: profile.phone,
    email: null,
    requestId: "create-target-1",
  });

  assert.deepEqual(created, profile);
  const call = calls.at(0);
  assert.ok(call);
  assert.match(call.text, /create_promotion_target/);
  assert.deepEqual(call.values, [
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    "22222222-2222-4222-8222-222222222222",
    "person",
    "王小明",
    "+1 312 555 0100",
    null,
    "create-target-1",
  ]);
});

test("relationship update returns an explicit conflict instead of overwriting", async () => {
  const store = new MemoryStore();
  store.relationshipUpdate = {
    status: "conflict",
    conflictId: "66666666-6666-4666-8666-666666666666",
    conflictingFields: ["stage"],
    current: relationship,
    proposed: {
      expectedRevision: 1,
      stage: 4,
      displayStage: 8,
      lifecycleStatus: "active",
      followUpNote: "安排下一次会面",
      reasonCode: "progress_update",
      reasonDetail: null,
    },
  };

  const result = await updatePromotionTargetRelationship(
    "Bearer token",
    profile.id,
    relationshipBody(),
    dependencies(store, [
      "view_assigned_target_pii",
      "manage_assigned_target_follow_up",
    ]),
  );

  assert.equal(result.status, 409);
  assert.equal(
    (result.body.current as {revision_number: number}).revision_number,
    2,
  );
  assert.equal(store.relationshipInput?.mutationId, "relationship-change-1");
});

test("relationship update rejects forged fields before calling the store", async () => {
  const store = new MemoryStore();
  const result = await updatePromotionTargetRelationship(
    "Bearer token",
    profile.id,
    {...relationshipBody(), project_id: "forged"},
    dependencies(store, [
      "view_assigned_target_pii",
      "manage_assigned_target_follow_up",
    ]),
  );

  assert.deepEqual(result, {
    status: 400,
    body: {error: {code: "invalid_promotion_target_relationship"}},
  });
  assert.equal(store.calls, 0);
});

test("stage aliases require project management capability and preserve 0-4", async () => {
  const store = new MemoryStore();
  const body = {
    aliases: aliases.map((alias) => ({
      stage: alias.stage,
      display_name: alias.displayName,
    })),
  };
  const forbidden = await configurePromotionTargetStageAliases(
    "Bearer token",
    body,
    dependencies(store, ["view_assigned_target_pii"]),
  );
  assert.equal(forbidden.status, 403);

  const accepted = await configurePromotionTargetStageAliases(
    "Bearer token",
    body,
    dependencies(store, [
      "manage_analysis_definitions",
    ]),
  );
  assert.equal(accepted.status, 200);
  assert.deepEqual(store.aliasInputs.map((alias) => alias.stage), [0, 1, 2, 3, 4]);
});

test("Postgres relationship adapter sends expected revision and mutation id", async () => {
  const calls: Array<{text: string; values: readonly unknown[]}> = [];
  const store = new PostgresPromotionTargetStore(async (text, values) => {
    calls.push({text, values});
    return {rows: [{result: relationshipUpdateDocument()}]};
  });

  const update = await store.updateRelationship(
    context([]),
    profile.id,
    {
      expectedRevision: 1,
      stage: 3,
      lifecycleStatus: "active",
      followUpNote: "下周再次联系",
      reasonCode: "progress_update",
      reasonDetail: null,
      mutationId: "relationship-change-1",
      resolvedConflictId: null,
    },
  );

  assert.equal(update.status, "accepted");
  assert.match(calls[0]?.text ?? "", /update_promotion_target_relationship/);
  assert.deepEqual(calls[0]?.values.slice(3), [
    profile.id,
    1,
    3,
    "active",
    "下周再次联系",
    "progress_update",
    null,
    "relationship-change-1",
    null,
  ]);
});

function validBody() {
  return {
    target_type: "person",
    display_name: "  王小明  ",
    phone: "  +1 312 555 0100  ",
    email: null,
    request_id: "create-target-1",
  };
}

function relationshipBody() {
  return {
    expected_revision: 1,
    stage: 4,
    lifecycle_status: "active",
    follow_up_note: "安排下一次会面",
    reason_code: "progress_update",
    reason_detail: null,
    mutation_id: "relationship-change-1",
    resolved_conflict_id: null,
  };
}

function relationshipUpdateDocument() {
  return {
    status: "accepted",
    duplicate: false,
    accepted_revision: 2,
    relationship: relationshipDocument(),
  };
}

function relationshipDocument() {
  return {
    target_id: relationship.targetId,
    project_id: relationship.projectId,
    stage: relationship.stage,
    display_stage: relationship.displayStage,
    lifecycle_status: relationship.lifecycleStatus,
    follow_up_note: relationship.followUpNote,
    revision_number: relationship.revisionNumber,
    updated_at: relationship.updatedAt,
    stage_aliases: aliases.map((alias) => ({
      stage: alias.stage,
      display_stage: alias.displayStage,
      display_name: alias.displayName,
    })),
    history: relationship.history.map((revision) => ({
      revision_number: revision.revisionNumber,
      old_stage: revision.oldStage,
      new_stage: revision.newStage,
      old_lifecycle_status: revision.oldLifecycleStatus,
      new_lifecycle_status: revision.newLifecycleStatus,
      follow_up_note: revision.followUpNote,
      changed_fields: revision.changedFields,
      reason_code: revision.reasonCode,
      reason_detail: revision.reasonDetail,
      changed_by_app_user_id: revision.changedByAppUserId,
      changed_at: revision.changedAt,
    })),
  };
}

function dependencies(
  targetStore: PromotionTargetStore,
  capabilities: readonly string[],
) {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => context(capabilities),
    },
    targetStore,
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

class MemoryStore implements PromotionTargetStore {
  calls = 0;
  created: CreatePromotionTargetInput | null = null;
  relationshipInput: UpdatePromotionTargetRelationshipInput | null = null;
  relationshipUpdate: PromotionTargetRelationshipUpdate = {
    status: "accepted",
    duplicate: false,
    acceptedRevision: 2,
    relationship,
  };
  aliasInputs: readonly PromotionTargetStageAliasInput[] = [];

  async listAssigned(): Promise<readonly PromotionTargetProfile[]> {
    this.calls += 1;
    return [profile];
  }

  async create(
    _context: SessionContext,
    input: CreatePromotionTargetInput,
  ): Promise<PromotionTargetProfile> {
    this.calls += 1;
    this.created = input;
    return profile;
  }

  async updateRelationship(
    _context: SessionContext,
    _targetId: string,
    input: UpdatePromotionTargetRelationshipInput,
  ): Promise<PromotionTargetRelationshipUpdate> {
    this.calls += 1;
    this.relationshipInput = input;
    return this.relationshipUpdate;
  }

  async configureStageAliases(
    _context: SessionContext,
    aliasInputs: readonly PromotionTargetStageAliasInput[],
  ): Promise<readonly PromotionTargetStageAlias[]> {
    this.calls += 1;
    this.aliasInputs = aliasInputs;
    return aliases;
  }
}
