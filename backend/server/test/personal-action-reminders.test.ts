import assert from "node:assert/strict";
import test from "node:test";

import {
  PersonalActionReminderStoreError,
  PostgresPersonalActionReminderStore,
  readPersonalActionReminder,
  savePersonalActionReminder,
  type PersonalActionReminder,
  type PersonalActionReminderDependencies,
} from "../src/personal-action-reminders.js";
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
  capabilities: [],
};

const reminder: PersonalActionReminder = {
  reminderId: "55555555-5555-4555-8555-555555555555",
  revision: 2,
  localMinuteOfDay: 19 * 60,
  updatedAt: "2030-03-09T18:00:00.000Z",
};

test("private reminder read uses verified current context without manager capability", async () => {
  let receivedContext: SessionContext | undefined;
  const result = await readPersonalActionReminder(
    "Bearer token",
    dependencies({
      read: async (value) => {
        receivedContext = value;
        return reminder;
      },
    }),
  );

  assert.equal(result.status, 200);
  assert.equal(receivedContext, context);
  assert.deepEqual(result.body, {reminder: serializedReminder});
});

test("reminder time is optional and independent from a weekly goal", async () => {
  let savedMinute: number | null | undefined;
  const deps = dependencies({
    save: async (_context, input) => {
      savedMinute = input.localMinuteOfDay;
      return {reminder, duplicate: false, acceptedRevision: 2};
    },
  });

  const enabled = await savePersonalActionReminder(
    "Bearer token",
    {
      expected_revision: 1,
      local_minute_of_day: 1140,
      mutation_id: "reminder-enable",
    },
    deps,
  );
  assert.equal(enabled.status, 200);
  assert.equal(savedMinute, 1140);

  const cleared = await savePersonalActionReminder(
    "Bearer token",
    {
      expected_revision: 1,
      local_minute_of_day: null,
      mutation_id: "reminder-clear",
    },
    deps,
  );
  assert.equal(cleared.status, 200);
  assert.equal(savedMinute, null);
});

test("reminder save rejects guessed fields and out-of-range times", async () => {
  let saveCount = 0;
  const deps = dependencies({
    save: async () => {
      saveCount++;
      return {reminder, duplicate: false, acceptedRevision: 2};
    },
  });

  for (const body of [
    {
      expected_revision: 1,
      local_minute_of_day: 1440,
      mutation_id: "invalid-minute",
    },
    {
      expected_revision: 1,
      local_minute_of_day: 600,
      mutation_id: "forged-scope",
      app_user_id: context.appUserId,
    },
  ]) {
    const result = await savePersonalActionReminder("Bearer token", body, deps);
    assert.equal(result.status, 400);
  }
  assert.equal(saveCount, 0);
});

test("reminder revision conflicts have a stable HTTP result", async () => {
  const result = await savePersonalActionReminder(
    "Bearer token",
    validInput,
    dependencies({
      save: async () => {
        throw new PersonalActionReminderStoreError("conflict");
      },
    }),
  );
  assert.deepEqual(result, {
    status: 409,
    body: {error: {code: "personal_action_reminder_conflict"}},
  });
});

test("Postgres reminder store binds trusted scope and service time", async () => {
  let sql = "";
  let values: readonly unknown[] = [];
  const store = new PostgresPersonalActionReminderStore(
    async (text, parameters) => {
      sql = text;
      values = parameters;
      return {
        rows: [{
          reminder: {
            ...databaseReminder,
            duplicate: false,
            accepted_revision: 2,
          },
        }],
      };
    },
  );
  const result = await store.save(
    context,
    {
      expectedRevision: 1,
      localMinuteOfDay: 1140,
      mutationId: "reminder-update",
    },
    "2030-03-09T18:00:00.000Z",
  );

  assert.match(sql, /save_personal_action_reminder/);
  assert.deepEqual(values, [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
    1,
    1140,
    "reminder-update",
    "2030-03-09T18:00:00.000Z",
  ]);
  assert.equal(result.reminder.localMinuteOfDay, 1140);
});

const validInput = {
  expected_revision: 1,
  local_minute_of_day: 1140,
  mutation_id: "reminder-update",
};

const serializedReminder = {
  reminder_id: reminder.reminderId,
  revision: reminder.revision,
  local_minute_of_day: reminder.localMinuteOfDay,
  updated_at_utc: reminder.updatedAt,
};

const databaseReminder = {
  reminder_id: reminder.reminderId,
  revision: reminder.revision,
  local_minute_of_day: reminder.localMinuteOfDay,
  updated_at_utc: reminder.updatedAt,
};

function dependencies(
  overrides: Partial<PersonalActionReminderDependencies["reminderStore"]> & {
    contextValue?: SessionContext;
  } = {},
): PersonalActionReminderDependencies {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {
      loadOrCreate: async () => overrides.contextValue ?? context,
    },
    reminderStore: {
      read: overrides.read ?? (async () => reminder),
      save: overrides.save ?? (async () => ({
        reminder,
        duplicate: false,
        acceptedRevision: reminder.revision,
      })),
    },
    now: () => new Date("2030-03-09T18:00:00.000Z"),
  };
}
