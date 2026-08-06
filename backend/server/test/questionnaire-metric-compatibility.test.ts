import assert from "node:assert/strict";
import test from "node:test";

import {
  listQuestionnaireMetricCompatibility,
  recordQuestionnaireMetricCompatibility,
  revokeQuestionnaireMetricCompatibility,
  type QuestionnaireMetricCompatibilityEvent,
  type QuestionnaireMetricCompatibilitySnapshot,
  type QuestionnaireMetricCompatibilityStore,
} from "../src/questionnaire-metric-compatibility.js";
import type { SessionContext } from "../src/session-context.js";

const metricId = "33333333-3333-4333-8333-333333333333";
const referenceVersionId = "11111111-1111-4111-8111-111111111111";
const candidateVersionId = "44444444-4444-4444-8444-444444444444";

test("each compatibility operation rechecks the trusted capability", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, ["record_contact"]);

  const results = await Promise.all([
    listQuestionnaireMetricCompatibility("Bearer valid-token", deps),
    recordQuestionnaireMetricCompatibility(
      "Bearer valid-token",
      decisionBody("compatible", "permission-record"),
      deps,
    ),
    revokeQuestionnaireMetricCompatibility(
      "Bearer valid-token",
      "55555555-5555-4555-8555-555555555555",
      {request_id: "permission-revoke", reason: "权限已撤销"},
      deps,
    ),
  ]);

  for (const result of results) {
    assert.deepEqual(result, {
      status: 403,
      body: {error: {code: "capability_forbidden"}},
    });
  }
  assert.equal(store.calls, 0);
});

test("manager records an explicit compatible decision and can revoke it", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, ["manage_analysis_definitions"]);

  const recorded = await recordQuestionnaireMetricCompatibility(
    "Bearer valid-token",
    decisionBody("compatible", "compatible-1"),
    deps,
  );
  assert.equal(recorded.status, 201);
  assert.equal(
    (recorded.body.event as {decision: string}).decision,
    "compatible",
  );
  assert.deepEqual(store.snapshot.metrics[0]?.activeMembers, [
    {questionnaireVersionId: referenceVersionId, questionId: "interest"},
    {questionnaireVersionId: candidateVersionId, questionId: "interest-v2"},
  ]);

  const eventId = (recorded.body.event as {event_id: string}).event_id;
  const revoked = await revokeQuestionnaireMetricCompatibility(
    "Bearer valid-token",
    eventId,
    {request_id: "revoke-1", reason: "候选问题的时间范围已改变"},
    deps,
  );
  assert.equal(revoked.status, 201);
  assert.equal((revoked.body.event as {action: string}).action, "revoked");
  assert.deepEqual(store.snapshot.metrics[0]?.activeMembers, [
    {questionnaireVersionId: referenceVersionId, questionId: "interest"},
  ]);
  assert.equal(store.snapshot.events.length, 2);
  assert.deepEqual(
    store.snapshot.events.map((event) => event.impactSnapshot),
    [impactSnapshot, impactSnapshot],
  );
});

test("incompatible decisions remain audited without joining the metric", async () => {
  const store = new MemoryStore();
  const result = await recordQuestionnaireMetricCompatibility(
    "Bearer valid-token",
    decisionBody("incompatible", "incompatible-1"),
    dependencies(store, ["manage_analysis_definitions"]),
  );

  assert.equal(result.status, 201);
  assert.deepEqual(store.snapshot.metrics[0]?.activeMembers, [
    {questionnaireVersionId: referenceVersionId, questionId: "interest"},
  ]);
  assert.equal(store.snapshot.events[0]?.decision, "incompatible");
});

test("HTTP validation rejects guessed, same-version, and incomplete decisions", async () => {
  const store = new MemoryStore();
  const deps = dependencies(store, ["manage_analysis_definitions"]);
  const sameVersion = {
    ...decisionBody("compatible", "same-version"),
    candidate: {
      questionnaire_version_id: referenceVersionId,
      question_id: "interest-v2",
    },
  };
  const guessed = {
    ...decisionBody("compatible", "guessed"),
    decision: "similar",
  };
  const noReason = {...decisionBody("compatible", "no-reason"), reason: " "};

  for (const body of [sameVersion, guessed, noReason]) {
    const result = await recordQuestionnaireMetricCompatibility(
      "Bearer valid-token",
      body,
      deps,
    );
    assert.equal(result.status, 400);
  }
  assert.equal(store.calls, 0);
});

function decisionBody(
  decision: "compatible" | "incompatible",
  requestId: string,
) {
  return {
    metric_id: metricId,
    metric_label: "接触兴趣",
    analysis_operation: "distribution",
    reference: {
      questionnaire_version_id: referenceVersionId,
      question_id: "interest",
    },
    candidate: {
      questionnaire_version_id: candidateVersionId,
      question_id: "interest-v2",
    },
    decision,
    reason: decision === "compatible"
      ? "定义、选项、时间范围和回答方式均未改变"
      : "候选问题的时间范围不同",
    request_id: requestId,
  };
}

const impactSnapshot = {
  referenceSampleCount: 12,
  candidateSampleCount: 8,
  combinedSampleCount: 20,
  separateSeries: [
    {questionnaireVersionId: referenceVersionId, sampleCount: 12},
    {questionnaireVersionId: candidateVersionId, sampleCount: 8},
  ],
  trendSeries: [],
};

function dependencies(
  compatibilityStore: QuestionnaireMetricCompatibilityStore,
  capabilities: readonly string[],
) {
  return {
    identityVerifier: {
      verify: async () => ({issuer: "issuer", subject: "subject"}),
    },
    contextStore: {loadOrCreate: async () => context(capabilities)},
    compatibilityStore,
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
      questionnaireVersion: {id: candidateVersionId, versionNumber: 2},
    },
    capabilities,
  };
}

class MemoryStore implements QuestionnaireMetricCompatibilityStore {
  calls = 0;
  private requestEvents = new Map<string, QuestionnaireMetricCompatibilityEvent>();
  snapshot: QuestionnaireMetricCompatibilitySnapshot = {
    metrics: [],
    availableQuestions: [],
    events: [],
  };

  async list(): Promise<QuestionnaireMetricCompatibilitySnapshot> {
    this.calls += 1;
    return this.snapshot;
  }

  async record(_context: SessionContext, input: Parameters<QuestionnaireMetricCompatibilityStore["record"]>[1]) {
    this.calls += 1;
    const replay = this.requestEvents.get(input.requestId);
    if (replay !== undefined) return replay;
    const event = eventFor(input, "decided");
    const activeMembers = [input.reference];
    if (input.decision === "compatible") activeMembers.push(input.candidate);
    this.snapshot = {
      metrics: [{
        id: input.metricId,
        label: input.metricLabel,
        analysisOperation: input.analysisOperation,
        activeMembers,
      }],
      availableQuestions: this.snapshot.availableQuestions,
      events: [...this.snapshot.events, event],
    };
    this.requestEvents.set(input.requestId, event);
    return event;
  }

  async revoke(_context: SessionContext, input: Parameters<QuestionnaireMetricCompatibilityStore["revoke"]>[1]) {
    this.calls += 1;
    const target = this.snapshot.events.find((event) => event.id === input.eventId);
    if (target === undefined) throw new Error("test target event missing");
    const event: QuestionnaireMetricCompatibilityEvent = {
      ...target,
      id: "66666666-6666-4666-8666-666666666666",
      action: "revoked",
      targetEventId: target.id,
      actorAppUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      reason: input.reason,
      createdAt: "2026-08-06T01:00:00.000Z",
    };
    const metric = this.snapshot.metrics[0]!;
    this.snapshot = {
      metrics: [{
        ...metric,
        activeMembers: metric.activeMembers.filter(
          (member) => member.questionnaireVersionId !== target.candidate.questionnaireVersionId ||
            member.questionId !== target.candidate.questionId,
        ),
      }],
      availableQuestions: this.snapshot.availableQuestions,
      events: [...this.snapshot.events, event],
    };
    return event;
  }
}

function eventFor(
  input: Parameters<QuestionnaireMetricCompatibilityStore["record"]>[1],
  action: "decided",
): QuestionnaireMetricCompatibilityEvent {
  return {
    id: "55555555-5555-4555-8555-555555555555",
    metricId: input.metricId,
    action,
    decision: input.decision,
    targetEventId: null,
    reference: input.reference,
    candidate: input.candidate,
    actorAppUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    reason: input.reason,
    comparisonSnapshot: {
      reference: {prompt: "兴趣程度", options: ["低", "高"]},
      candidate: {prompt: "兴趣程度", options: ["低", "高"]},
      timeScope: "all_recorded_contacts",
      answerMode: "single_choice",
    },
    impactSnapshot,
    createdAt: "2026-08-06T00:00:00.000Z",
  };
}
