import assert from "node:assert/strict";
import test from "node:test";

import {
  PersonalActionPlanStoreError,
  PostgresPersonalActionPlanStore,
  readPersonalActionPlan,
  savePersonalActionPlan,
  type PersonalActionPlan,
  type PersonalActionPlanDependencies,
} from "../src/personal-action-plans.js";
import type {SessionContext} from "../src/session-context.js";

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
  capabilities: ["record_contact"],
};

const plan: PersonalActionPlan = {
  planId: "55555555-5555-4555-8555-555555555555",
  revision: 2,
  current: {
    revision: 1,
    weeklyContactTarget: 3,
    statisticsTimeZone: "America/Chicago",
    weekStartIsoDay: 1,
    effectiveFrom: "2030-03-04T06:00:00.000Z",
  },
  pending: {
    revision: 2,
    weeklyContactTarget: 4,
    statisticsTimeZone: "Asia/Shanghai",
    weekStartIsoDay: 7,
    effectiveFrom: "2030-03-16T16:00:00.000Z",
  },
  progress: {
    cycleStart: "2030-03-04T06:00:00.000Z",
    cycleUntil: "2030-03-11T05:00:00.000Z",
    recordedContactSessions: 1,
    remainingContactSessions: 2,
    asOf: "2030-03-09T18:00:00.000Z",
  },
};

test("private plan read uses the verified current context", async () => {
  let receivedContext: SessionContext | undefined;
  let referenceAt: string | undefined;
  const result = await readPersonalActionPlan(
    "Bearer token",
    dependencies({
      read: async (value, time) => {
        receivedContext = value;
        referenceAt = time;
        return plan;
      },
    }),
  );

  assert.equal(result.status, 200);
  assert.equal(receivedContext, context);
  assert.equal(referenceAt, "2030-03-09T18:00:00.000Z");
  assert.deepEqual(result.body, {plan: serializedPlan});
});

test("private plan endpoint has no manager capability requirement", async () => {
  const withoutManagerCapability = {...context, capabilities: []};
  const result = await readPersonalActionPlan(
    "Bearer token",
    dependencies({contextValue: withoutManagerCapability}),
  );
  assert.equal(result.status, 200);
});

test("save validates the full private plan payload before store access", async () => {
  let saveCount = 0;
  const deps = dependencies({
    save: async () => {
      saveCount++;
      return {plan, duplicate: false, acceptedRevision: 2};
    },
  });
  const invalid = await savePersonalActionPlan(
    "Bearer token",
    {
      expected_revision: 1,
      weekly_contact_target: 0,
      statistics_time_zone: "America/Chicago",
      week_start_iso_day: 1,
      mutation_id: "mutation-1",
    },
    deps,
  );
  assert.equal(invalid.status, 400);
  assert.equal(saveCount, 0);

  const saved = await savePersonalActionPlan(
    "Bearer token",
    {
      expected_revision: 1,
      weekly_contact_target: null,
      statistics_time_zone: "America/Chicago",
      week_start_iso_day: 7,
      mutation_id: "mutation-2",
    },
    deps,
  );
  assert.equal(saved.status, 200);
  assert.equal(saveCount, 1);
});

test("revision and pending conflicts have stable HTTP results", async () => {
  const conflict = await savePersonalActionPlan(
    "Bearer token",
    validInput,
    dependencies({
      save: async () => {
        throw new PersonalActionPlanStoreError("conflict");
      },
    }),
  );
  const pending = await savePersonalActionPlan(
    "Bearer token",
    validInput,
    dependencies({
      save: async () => {
        throw new PersonalActionPlanStoreError("pending");
      },
    }),
  );
  assert.deepEqual(conflict, {
    status: 409,
    body: {error: {code: "personal_action_plan_conflict"}},
  });
  assert.deepEqual(pending, {
    status: 409,
    body: {error: {code: "personal_action_plan_pending_change"}},
  });
});

test("Postgres store binds trusted scope, payload, and service time", async () => {
  let sql = "";
  let values: readonly unknown[] = [];
  const store = new PostgresPersonalActionPlanStore(async (text, parameters) => {
    sql = text;
    values = parameters;
    return {rows: [{plan: {...databasePlan, duplicate: false, accepted_revision: 2}}]};
  });
  const result = await store.save(
    context,
    {
      expectedRevision: 1,
      weeklyContactTarget: 4,
      statisticsTimeZone: "Asia/Shanghai",
      weekStartIsoDay: 7,
      mutationId: "mutation-2",
    },
    "2030-03-09T18:00:00.000Z",
  );

  assert.match(sql, /save_personal_action_plan/);
  assert.deepEqual(values, [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
    1,
    4,
    "Asia/Shanghai",
    7,
    "mutation-2",
    "2030-03-09T18:00:00.000Z",
  ]);
  assert.equal(result.plan.progress.remainingContactSessions, 2);
});

const validInput = {
  expected_revision: 1,
  weekly_contact_target: 4,
  statistics_time_zone: "Asia/Shanghai",
  week_start_iso_day: 7,
  mutation_id: "mutation-2",
};

const serializedPlan = {
  plan_id: plan.planId,
  revision: 2,
  current: {
    revision: 1,
    weekly_contact_target: 3,
    statistics_time_zone: "America/Chicago",
    week_start_iso_day: 1,
    effective_from_utc: "2030-03-04T06:00:00.000Z",
  },
  pending: {
    revision: 2,
    weekly_contact_target: 4,
    statistics_time_zone: "Asia/Shanghai",
    week_start_iso_day: 7,
    effective_from_utc: "2030-03-16T16:00:00.000Z",
  },
  progress: {
    cycle_start_utc: "2030-03-04T06:00:00.000Z",
    cycle_until_utc: "2030-03-11T05:00:00.000Z",
    recorded_contact_sessions: 1,
    remaining_contact_sessions: 2,
    as_of_utc: "2030-03-09T18:00:00.000Z",
  },
};

const databasePlan = {
  ...serializedPlan,
  current: serializedPlan.current,
  pending: serializedPlan.pending,
};

function dependencies(overrides?: {
  readonly contextValue?: SessionContext;
  readonly read?: PersonalActionPlanDependencies["planStore"]["read"];
  readonly save?: PersonalActionPlanDependencies["planStore"]["save"];
}): PersonalActionPlanDependencies {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => overrides?.contextValue ?? context,
    },
    planStore: {
      read: overrides?.read ?? (async () => null),
      save: overrides?.save ?? (async () => ({
        plan,
        duplicate: false,
        acceptedRevision: 2,
      })),
    },
    now: () => new Date("2030-03-09T18:00:00.000Z"),
  };
}
