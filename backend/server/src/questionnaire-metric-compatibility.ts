import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";
import type {
  SessionContext,
  SessionContextStore,
} from "./session-context.js";

export const questionnaireMetricManagementCapability =
  "manage_analysis_definitions";

export type QuestionnaireMetricAnalysisOperation =
  | "count"
  | "distribution"
  | "proportion";
export type QuestionnaireMetricDecision = "compatible" | "incompatible";
export type QuestionnaireMetricCompatibilityAction = "decided" | "revoked";

export interface QuestionnaireMetricQuestionReference {
  readonly questionnaireVersionId: string;
  readonly questionId: string;
}

export interface QuestionnaireMetricImpactSeries {
  readonly questionnaireVersionId: string;
  readonly sampleCount: number;
}

export interface QuestionnaireMetricQuestionTrendPoint {
  readonly periodStart: string;
  readonly sampleCount: number;
}

export interface QuestionnaireMetricImpactTrendPoint {
  readonly periodStart: string;
  readonly referenceSampleCount: number;
  readonly candidateSampleCount: number;
  readonly combinedSampleCount: number;
}

export interface QuestionnaireMetricImpactSnapshot {
  readonly referenceSampleCount: number;
  readonly candidateSampleCount: number;
  readonly combinedSampleCount: number;
  readonly separateSeries: readonly QuestionnaireMetricImpactSeries[];
  readonly trendSeries: readonly QuestionnaireMetricImpactTrendPoint[];
}

export interface QuestionnaireMetricCompatibilityEvent {
  readonly id: string;
  readonly metricId: string;
  readonly action: QuestionnaireMetricCompatibilityAction;
  readonly decision: QuestionnaireMetricDecision;
  readonly targetEventId: string | null;
  readonly reference: QuestionnaireMetricQuestionReference;
  readonly candidate: QuestionnaireMetricQuestionReference;
  readonly actorAppUserId: string;
  readonly reason: string;
  readonly comparisonSnapshot: Readonly<Record<string, unknown>>;
  readonly impactSnapshot: QuestionnaireMetricImpactSnapshot;
  readonly createdAt: string;
}

export interface QuestionnaireMetricDefinition {
  readonly id: string;
  readonly label: string;
  readonly analysisOperation: QuestionnaireMetricAnalysisOperation;
  readonly activeMembers: readonly QuestionnaireMetricQuestionReference[];
}

export interface QuestionnaireMetricQuestionCandidate {
  readonly reference: QuestionnaireMetricQuestionReference;
  readonly versionNumber: number;
  readonly comparisonSnapshot: Readonly<Record<string, unknown>>;
  readonly sampleCount: number;
  readonly trendSeries: readonly QuestionnaireMetricQuestionTrendPoint[];
}

export interface QuestionnaireMetricCompatibilitySnapshot {
  readonly metrics: readonly QuestionnaireMetricDefinition[];
  readonly availableQuestions: readonly QuestionnaireMetricQuestionCandidate[];
  readonly events: readonly QuestionnaireMetricCompatibilityEvent[];
}

export interface RecordQuestionnaireMetricCompatibilityInput {
  readonly metricId: string;
  readonly metricLabel: string;
  readonly analysisOperation: QuestionnaireMetricAnalysisOperation;
  readonly reference: QuestionnaireMetricQuestionReference;
  readonly candidate: QuestionnaireMetricQuestionReference;
  readonly decision: QuestionnaireMetricDecision;
  readonly reason: string;
  readonly requestId: string;
}

export interface RevokeQuestionnaireMetricCompatibilityInput {
  readonly eventId: string;
  readonly reason: string;
  readonly requestId: string;
}

export interface QuestionnaireMetricCompatibilityStore {
  list(context: SessionContext): Promise<QuestionnaireMetricCompatibilitySnapshot>;
  record(
    context: SessionContext,
    input: RecordQuestionnaireMetricCompatibilityInput,
  ): Promise<QuestionnaireMetricCompatibilityEvent>;
  revoke(
    context: SessionContext,
    input: RevokeQuestionnaireMetricCompatibilityInput,
  ): Promise<QuestionnaireMetricCompatibilityEvent>;
}

export interface QuestionnaireMetricCompatibilityDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly contextStore: SessionContextStore;
  readonly compatibilityStore: QuestionnaireMetricCompatibilityStore;
}

export interface QuestionnaireMetricCompatibilityHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

export async function listQuestionnaireMetricCompatibility(
  authorization: string | undefined,
  dependencies: QuestionnaireMetricCompatibilityDependencies,
): Promise<QuestionnaireMetricCompatibilityHttpResult> {
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const snapshot = await dependencies.compatibilityStore.list(context.value);
    return {status: 200, body: serializeSnapshot(snapshot)};
  } catch (error) {
    return storeFailure(error);
  }
}

export async function recordQuestionnaireMetricCompatibility(
  authorization: string | undefined,
  body: unknown,
  dependencies: QuestionnaireMetricCompatibilityDependencies,
): Promise<QuestionnaireMetricCompatibilityHttpResult> {
  const input = parseRecordInput(body);
  if (input === null) {
    return failure(400, "invalid_questionnaire_metric_decision");
  }
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const event = await dependencies.compatibilityStore.record(
      context.value,
      input,
    );
    return {status: 201, body: {event: serializeEvent(event)}};
  } catch (error) {
    return storeFailure(error);
  }
}

export async function revokeQuestionnaireMetricCompatibility(
  authorization: string | undefined,
  eventId: string,
  body: unknown,
  dependencies: QuestionnaireMetricCompatibilityDependencies,
): Promise<QuestionnaireMetricCompatibilityHttpResult> {
  const root = record(body);
  const reason = boundedString(root.reason, 1, 1000);
  const requestId = boundedString(root.request_id, 1, 120);
  if (!uuidPattern.test(eventId) || reason === null || requestId === null) {
    return failure(400, "invalid_questionnaire_metric_revocation");
  }
  const context = await authorizedContext(authorization, dependencies);
  if (!(context instanceof AuthorizedContext)) return context;
  try {
    const event = await dependencies.compatibilityStore.revoke(
      context.value,
      {eventId, reason, requestId},
    );
    return {status: 201, body: {event: serializeEvent(event)}};
  } catch (error) {
    return storeFailure(error);
  }
}

export type QuestionnaireMetricCompatibilityQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{readonly rows: readonly unknown[]}>;

export class PostgresQuestionnaireMetricCompatibilityStore
  implements QuestionnaireMetricCompatibilityStore {
  constructor(private readonly query: QuestionnaireMetricCompatibilityQuery) {}

  async list(
    context: SessionContext,
  ): Promise<QuestionnaireMetricCompatibilitySnapshot> {
    return parseSnapshot(await this.oneJson(
      `SELECT compatibility
       FROM app_data.list_questionnaire_metric_compatibility(
         $1::uuid, $2::uuid, $3::uuid
       )`,
      contextValues(context),
      "compatibility",
    ));
  }

  async record(
    context: SessionContext,
    input: RecordQuestionnaireMetricCompatibilityInput,
  ): Promise<QuestionnaireMetricCompatibilityEvent> {
    return parseEvent(await this.oneJson(
      `SELECT event
       FROM app_data.record_questionnaire_metric_compatibility(
         $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::text, $6::text,
         $7::uuid, $8::text, $9::uuid, $10::text, $11::text,
         $12::text, $13::text
       )`,
      [
        ...contextValues(context),
        input.metricId,
        input.metricLabel,
        input.analysisOperation,
        input.reference.questionnaireVersionId,
        input.reference.questionId,
        input.candidate.questionnaireVersionId,
        input.candidate.questionId,
        input.decision,
        input.reason,
        input.requestId,
      ],
      "event",
    ));
  }

  async revoke(
    context: SessionContext,
    input: RevokeQuestionnaireMetricCompatibilityInput,
  ): Promise<QuestionnaireMetricCompatibilityEvent> {
    return parseEvent(await this.oneJson(
      `SELECT event
       FROM app_data.revoke_questionnaire_metric_compatibility(
         $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::text, $6::text
       )`,
      [...contextValues(context), input.eventId, input.reason, input.requestId],
      "event",
    ));
  }

  private async oneJson(
    sql: string,
    values: readonly unknown[],
    field: string,
  ): Promise<unknown> {
    try {
      const result = await this.query(sql, values);
      if (result.rows.length !== 1) {
        throw new Error(`${field} function must return exactly one row`);
      }
      return rowField(result.rows[0], field);
    } catch (error) {
      throw mapPostgresError(error);
    }
  }
}

export class QuestionnaireMetricCompatibilityStoreError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "QuestionnaireMetricCompatibilityStoreError";
  }
}

function parseRecordInput(
  value: unknown,
): RecordQuestionnaireMetricCompatibilityInput | null {
  const root = record(value);
  const metricId = uuid(root.metric_id);
  const metricLabel = boundedString(root.metric_label, 1, 200);
  const analysisOperation = enumValue(
    root.analysis_operation,
    ["count", "distribution", "proportion"] as const,
  );
  const reference = questionReference(root.reference);
  const candidate = questionReference(root.candidate);
  const decision = enumValue(
    root.decision,
    ["compatible", "incompatible"] as const,
  );
  const reason = boundedString(root.reason, 1, 1000);
  const requestId = boundedString(root.request_id, 1, 120);
  if (
    metricId === null || metricLabel === null || analysisOperation === null ||
    reference === null || candidate === null || decision === null ||
    reason === null || requestId === null ||
    reference.questionnaireVersionId === candidate.questionnaireVersionId
  ) return null;
  return {
    metricId,
    metricLabel,
    analysisOperation,
    reference,
    candidate,
    decision,
    reason,
    requestId,
  };
}

async function authorizedContext(
  authorization: string | undefined,
  dependencies: QuestionnaireMetricCompatibilityDependencies,
): Promise<AuthorizedContext | QuestionnaireMetricCompatibilityHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) return failure(401, "unauthenticated");
  try {
    const identity = await dependencies.identityVerifier.verify(accessToken);
    const context = await dependencies.contextStore.loadOrCreate(identity);
    return context.capabilities.includes(questionnaireMetricManagementCapability)
      ? new AuthorizedContext(context)
      : failure(403, "capability_forbidden");
  } catch (error) {
    return error instanceof IdentityVerificationError
      ? failure(401, "unauthenticated")
      : failure(503, "questionnaire_metric_compatibility_unavailable");
  }
}

class AuthorizedContext {
  constructor(readonly value: SessionContext) {}
}

function serializeSnapshot(
  snapshot: QuestionnaireMetricCompatibilitySnapshot,
): Readonly<Record<string, unknown>> {
  return {
    metrics: snapshot.metrics.map((metric) => ({
      metric_id: metric.id,
      metric_label: metric.label,
      analysis_operation: metric.analysisOperation,
      active_members: metric.activeMembers.map(serializeReference),
    })),
    available_questions: snapshot.availableQuestions.map((question) => ({
      reference: serializeReference(question.reference),
      version_number: question.versionNumber,
      comparison_snapshot: question.comparisonSnapshot,
      sample_count: question.sampleCount,
      trend_series: question.trendSeries.map((point) => ({
        period_start: point.periodStart,
        sample_count: point.sampleCount,
      })),
    })),
    events: snapshot.events.map(serializeEvent),
  };
}

function serializeEvent(
  event: QuestionnaireMetricCompatibilityEvent,
): Readonly<Record<string, unknown>> {
  return {
    event_id: event.id,
    metric_id: event.metricId,
    action: event.action,
    decision: event.decision,
    target_event_id: event.targetEventId,
    reference: serializeReference(event.reference),
    candidate: serializeReference(event.candidate),
    actor_app_user_id: event.actorAppUserId,
    reason: event.reason,
    comparison_snapshot: event.comparisonSnapshot,
    impact_snapshot: {
      reference_sample_count: event.impactSnapshot.referenceSampleCount,
      candidate_sample_count: event.impactSnapshot.candidateSampleCount,
      combined_sample_count: event.impactSnapshot.combinedSampleCount,
      separate_series: event.impactSnapshot.separateSeries.map((series) => ({
        questionnaire_version_id: series.questionnaireVersionId,
        sample_count: series.sampleCount,
      })),
      trend_series: event.impactSnapshot.trendSeries.map((point) => ({
        period_start: point.periodStart,
        reference_sample_count: point.referenceSampleCount,
        candidate_sample_count: point.candidateSampleCount,
        combined_sample_count: point.combinedSampleCount,
      })),
    },
    created_at: event.createdAt,
  };
}

function serializeReference(reference: QuestionnaireMetricQuestionReference) {
  return {
    questionnaire_version_id: reference.questionnaireVersionId,
    question_id: reference.questionId,
  };
}

function parseSnapshot(value: unknown): QuestionnaireMetricCompatibilitySnapshot {
  const root = record(value);
  return {
    metrics: array(root.metrics).map((entry) => {
      const metric = record(entry);
      return {
        id: requiredString(metric.metric_id),
        label: requiredString(metric.metric_label),
        analysisOperation: requiredEnum(
          metric.analysis_operation,
          ["count", "distribution", "proportion"] as const,
        ),
        activeMembers: array(metric.active_members).map(requiredReference),
      };
    }),
    availableQuestions: array(root.available_questions).map((entry) => {
      const question = record(entry);
      return {
        reference: requiredReference(question.reference),
        versionNumber: positiveInteger(question.version_number),
        comparisonSnapshot: record(question.comparison_snapshot),
        sampleCount: nonNegativeInteger(question.sample_count),
        trendSeries: array(question.trend_series).map((entry) => {
          const point = record(entry);
          return {
            periodStart: requiredString(point.period_start),
            sampleCount: nonNegativeInteger(point.sample_count),
          };
        }),
      };
    }),
    events: array(root.events).map(parseEvent),
  };
}

function parseEvent(value: unknown): QuestionnaireMetricCompatibilityEvent {
  const root = record(value);
  const impact = record(root.impact_snapshot);
  return {
    id: requiredString(root.event_id),
    metricId: requiredString(root.metric_id),
    action: requiredEnum(root.action, ["decided", "revoked"] as const),
    decision: requiredEnum(
      root.decision,
      ["compatible", "incompatible"] as const,
    ),
    targetEventId: root.target_event_id === null
      ? null
      : requiredString(root.target_event_id),
    reference: requiredReference(root.reference),
    candidate: requiredReference(root.candidate),
    actorAppUserId: requiredString(root.actor_app_user_id),
    reason: requiredString(root.reason),
    comparisonSnapshot: record(root.comparison_snapshot),
    impactSnapshot: {
      referenceSampleCount: nonNegativeInteger(impact.reference_sample_count),
      candidateSampleCount: nonNegativeInteger(impact.candidate_sample_count),
      combinedSampleCount: nonNegativeInteger(impact.combined_sample_count),
      separateSeries: array(impact.separate_series).map((entry) => {
        const series = record(entry);
        return {
          questionnaireVersionId: requiredString(
            series.questionnaire_version_id,
          ),
          sampleCount: nonNegativeInteger(series.sample_count),
        };
      }),
      trendSeries: array(impact.trend_series).map((entry) => {
        const point = record(entry);
        return {
          periodStart: requiredString(point.period_start),
          referenceSampleCount: nonNegativeInteger(
            point.reference_sample_count,
          ),
          candidateSampleCount: nonNegativeInteger(
            point.candidate_sample_count,
          ),
          combinedSampleCount: nonNegativeInteger(
            point.combined_sample_count,
          ),
        };
      }),
    },
    createdAt: requiredString(root.created_at),
  };
}

function requiredReference(value: unknown): QuestionnaireMetricQuestionReference {
  const parsed = questionReference(value);
  if (parsed === null) throw new TypeError("invalid question reference");
  return parsed;
}

function questionReference(
  value: unknown,
): QuestionnaireMetricQuestionReference | null {
  const root = record(value);
  const questionnaireVersionId = uuid(root.questionnaire_version_id);
  const questionId = boundedString(root.question_id, 1, 120);
  return questionnaireVersionId === null || questionId === null
    ? null
    : {questionnaireVersionId, questionId};
}

function contextValues(context: SessionContext): readonly string[] {
  return [
    context.appUserId,
    context.current.workspace.id,
    context.current.project.id,
  ];
}

function mapPostgresError(error: unknown): unknown {
  if (error instanceof QuestionnaireMetricCompatibilityStoreError) return error;
  const code = record(error).code;
  const message = record(error).message;
  if (code === "42501") {
    return new QuestionnaireMetricCompatibilityStoreError("forbidden");
  }
  if (code === "23505" || message === "questionnaire metric decision conflict") {
    return new QuestionnaireMetricCompatibilityStoreError("conflict");
  }
  if (code === "P0002" || message === "questionnaire metric event not found") {
    return new QuestionnaireMetricCompatibilityStoreError("not_found");
  }
  if (code === "22023") {
    return new QuestionnaireMetricCompatibilityStoreError("invalid_decision");
  }
  return error;
}

function storeFailure(error: unknown): QuestionnaireMetricCompatibilityHttpResult {
  if (error instanceof QuestionnaireMetricCompatibilityStoreError) {
    return switchFailure(error.code);
  }
  return failure(503, "questionnaire_metric_compatibility_unavailable");
}

function switchFailure(code: string): QuestionnaireMetricCompatibilityHttpResult {
  switch (code) {
    case "forbidden": return failure(403, "capability_forbidden");
    case "not_found": return failure(404, "questionnaire_metric_event_not_found");
    case "conflict": return failure(409, "questionnaire_metric_decision_conflict");
    case "invalid_decision": return failure(400, "invalid_questionnaire_metric_decision");
    default: return failure(503, "questionnaire_metric_compatibility_unavailable");
  }
}

function failure(
  status: number,
  code: string,
): QuestionnaireMetricCompatibilityHttpResult {
  return {status, body: {error: {code}}};
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function array(value: unknown): readonly unknown[] {
  if (!Array.isArray(value)) throw new TypeError("expected array");
  return value;
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

function boundedString(
  value: unknown,
  minimum: number,
  maximum: number,
): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length >= minimum && normalized.length <= maximum
    ? normalized
    : null;
}

function enumValue<const T extends readonly string[]>(
  value: unknown,
  allowed: T,
): T[number] | null {
  return typeof value === "string" && allowed.includes(value) ? value : null;
}

function requiredEnum<const T extends readonly string[]>(
  value: unknown,
  allowed: T,
): T[number] {
  const parsed = enumValue(value, allowed);
  if (parsed === null) throw new TypeError("invalid enum value");
  return parsed;
}

function requiredString(value: unknown): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError("expected non-empty string");
  }
  return value;
}

function nonNegativeInteger(value: unknown): number {
  if (!Number.isInteger(value) || (value as number) < 0) {
    throw new TypeError("expected non-negative integer");
  }
  return value as number;
}

function positiveInteger(value: unknown): number {
  if (!Number.isInteger(value) || (value as number) < 1) {
    throw new TypeError("expected positive integer");
  }
  return value as number;
}

function rowField(row: unknown, field: string): unknown {
  const value = record(row)[field];
  if (value === undefined) throw new TypeError(`missing ${field}`);
  return value;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
