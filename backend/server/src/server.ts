import { createServer, type Server } from "node:http";

import {
  createPersonalProject,
  getSessionContext,
  selectSessionProject,
  type SessionContextHttpDependencies,
} from "./http-app.js";
import { handleSyncChanges } from "./sync-changes.js";
import {
  handleSyncCommand,
  handleSyncCommandBatch,
} from "./sync-command.js";
import type { SyncCommandStore } from "./sync-store.js";
import {
  resolveContactRegion,
  type RegionResolutionStore,
} from "./region-resolution.js";
import {
  readPublishedQuestionnaire,
  type QuestionnaireStore,
} from "./questionnaire-catalog.js";
import {
  createQuestionnaireDraft,
  listQuestionnaireAdministration,
  publishQuestionnaireDraft,
  readQuestionnaireDraft,
  updateQuestionnaireDraft,
  type QuestionnaireAdministrationStore,
} from "./questionnaire-administration.js";
import {
  listQuestionnaireMetricCompatibility,
  recordQuestionnaireMetricCompatibility,
  revokeQuestionnaireMetricCompatibility,
  type QuestionnaireMetricCompatibilityStore,
} from "./questionnaire-metric-compatibility.js";
import {
  applyPromotionTargetRetentionAction,
  configurePromotionTargetStageAliases,
  createPromotionTarget,
  listAssignedPromotionTargets,
  listPromotionTargetRetentionTasks,
  updatePromotionTargetRelationship,
  type PromotionTargetRetentionStore,
  type PromotionTargetStore,
} from "./promotion-targets.js";
import {
  createTargetInstitutionRelationship,
  endTargetInstitutionRelationship,
  listTargetInstitutionRelationships,
  type TargetInstitutionRelationshipStore,
} from "./target-institution-relationships.js";
import {
  readPersonalActionPlan,
  savePersonalActionPlan,
  type PersonalActionPlanStore,
} from "./personal-action-plans.js";

export interface BackendServerDependencies
  extends SessionContextHttpDependencies {
  readonly commandStore?: SyncCommandStore;
  readonly regionResolutionStore?: RegionResolutionStore;
  readonly questionnaireStore?: QuestionnaireStore;
  readonly questionnaireAdministrationStore?: QuestionnaireAdministrationStore;
  readonly questionnaireMetricCompatibilityStore?:
    QuestionnaireMetricCompatibilityStore;
  readonly promotionTargetStore?: PromotionTargetStore;
  readonly promotionTargetRetentionStore?: PromotionTargetRetentionStore;
  readonly targetInstitutionRelationshipStore?:
    TargetInstitutionRelationshipStore;
  readonly personalActionPlanStore?: PersonalActionPlanStore;
}

export function createBackendServer(
  dependencies: BackendServerDependencies,
): Server {
  return createServer(async (request, response) => {
    response.setHeader("content-type", "application/json; charset=utf-8");
    response.setHeader("cache-control", "no-store");
    const requestUrl = new URL(request.url ?? "/", "http://localhost");

    if (request.method === "GET" && request.url === "/healthz") {
      response.statusCode = 200;
      response.end(JSON.stringify({ status: "ok" }));
      return;
    }

    if (request.method === "POST" && request.url === "/v1/regions/resolve") {
      if (dependencies.regionResolutionStore === undefined) {
        response.statusCode = 503;
        response.end(
          JSON.stringify({
            error: { code: "region_resolution_unavailable" },
          }),
        );
        return;
      }
      try {
        const body = await readJsonBody(request);
        const result = await resolveContactRegion(
          request.headers.authorization,
          body,
          {
            identityVerifier: dependencies.identityVerifier,
            regionResolutionStore: dependencies.regionResolutionStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        response.statusCode = error instanceof PayloadTooLargeError ? 413 : 400;
        response.end(
          JSON.stringify({
            error: {
              code:
                error instanceof PayloadTooLargeError
                  ? "payload_too_large"
                  : "invalid_json",
            },
          }),
        );
      }
      return;
    }

    if (
      request.method === "POST" &&
      (request.url === "/v1/sync/commands" ||
        request.url === "/v1/sync/commands/batch")
    ) {
      if (dependencies.commandStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({ error: { code: "sync_unavailable" } }));
        return;
      }
      try {
        const body = await readJsonBody(request);
        const handler = request.url === "/v1/sync/commands/batch"
          ? handleSyncCommandBatch
          : handleSyncCommand;
        const result = await handler(request.headers.authorization, body, {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          commandStore: dependencies.commandStore,
        });
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        response.statusCode = error instanceof PayloadTooLargeError ? 413 : 400;
        response.end(
          JSON.stringify({
            error: {
              code:
                error instanceof PayloadTooLargeError
                  ? "payload_too_large"
                  : "invalid_json",
            },
          }),
        );
      }
      return;
    }

    if (
      request.method === "POST" &&
      request.url === "/v1/session/context/select"
    ) {
      try {
        const body = await readJsonBody(request);
        const result = await selectSessionProject(
          request.headers.authorization,
          body,
          dependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        response.statusCode = error instanceof PayloadTooLargeError ? 413 : 400;
        response.end(
          JSON.stringify({
            error: {
              code:
                error instanceof PayloadTooLargeError
                  ? "payload_too_large"
                  : "invalid_json",
            },
          }),
        );
      }
      return;
    }

    if (
      request.method === "POST" &&
      request.url === "/v1/session/projects"
    ) {
      try {
        const body = await readJsonBody(request);
        const result = await createPersonalProject(
          request.headers.authorization,
          body,
          dependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        response.statusCode = error instanceof PayloadTooLargeError ? 413 : 400;
        response.end(
          JSON.stringify({
            error: {
              code:
                error instanceof PayloadTooLargeError
                  ? "payload_too_large"
                  : "invalid_json",
            },
          }),
        );
      }
      return;
    }

    if (
      requestUrl.pathname ===
        "/v1/promotion-target-institution-relationships" &&
      (request.method === "GET" || request.method === "POST")
    ) {
      if (dependencies.targetInstitutionRelationshipStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "target_institution_relationships_unavailable"},
        }));
        return;
      }
      const relationshipDependencies = {
        identityVerifier: dependencies.identityVerifier,
        contextStore: dependencies.contextStore,
        relationshipStore: dependencies.targetInstitutionRelationshipStore,
      };
      if (request.method === "GET") {
        const result = await listTargetInstitutionRelationships(
          request.headers.authorization,
          relationshipDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
        return;
      }
      try {
        const result = await createTargetInstitutionRelationship(
          request.headers.authorization,
          await readJsonBody(request),
          relationshipDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    const institutionRelationshipEndMatch = requestUrl.pathname.match(
      /^\/v1\/promotion-target-institution-relationships\/([^/]+)\/end$/,
    );
    if (
      request.method === "POST" &&
      institutionRelationshipEndMatch !== null
    ) {
      if (dependencies.targetInstitutionRelationshipStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "target_institution_relationships_unavailable"},
        }));
        return;
      }
      try {
        const result = await endTargetInstitutionRelationship(
          request.headers.authorization,
          institutionRelationshipEndMatch[1] ?? "",
          await readJsonBody(request),
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            relationshipStore:
              dependencies.targetInstitutionRelationshipStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    if (
      requestUrl.pathname === "/v1/promotion-targets" &&
      (request.method === "GET" || request.method === "POST")
    ) {
      if (dependencies.promotionTargetStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "promotion_targets_unavailable"},
        }));
        return;
      }
      const targetDependencies = {
        identityVerifier: dependencies.identityVerifier,
        contextStore: dependencies.contextStore,
        targetStore: dependencies.promotionTargetStore,
      };
      if (request.method === "GET") {
        const result = await listAssignedPromotionTargets(
          request.headers.authorization,
          targetDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
        return;
      }
      try {
        const result = await createPromotionTarget(
          request.headers.authorization,
          await readJsonBody(request),
          targetDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    const relationshipMatch = requestUrl.pathname.match(
      /^\/v1\/promotion-targets\/([^/]+)\/relationship$/,
    );

    if (
      request.method === "GET" &&
      requestUrl.pathname === "/v1/promotion-target-retention-tasks"
    ) {
      if (dependencies.promotionTargetRetentionStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "promotion_target_retention_unavailable"},
        }));
        return;
      }
      const result = await listPromotionTargetRetentionTasks(
        request.headers.authorization,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          targetStore: dependencies.promotionTargetRetentionStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const retentionMatch = requestUrl.pathname.match(
      /^\/v1\/promotion-targets\/([^/]+)\/retention$/,
    );
    if (request.method === "POST" && retentionMatch !== null) {
      if (dependencies.promotionTargetRetentionStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "promotion_target_retention_unavailable"},
        }));
        return;
      }
      try {
        const result = await applyPromotionTargetRetentionAction(
          request.headers.authorization,
          retentionMatch[1] ?? "",
          await readJsonBody(request),
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            targetStore: dependencies.promotionTargetRetentionStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    if (
      requestUrl.pathname === "/v1/personal-action-plan" &&
      (request.method === "GET" || request.method === "PUT")
    ) {
      if (dependencies.personalActionPlanStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "personal_action_plan_unavailable"},
        }));
        return;
      }
      const planDependencies = {
        identityVerifier: dependencies.identityVerifier,
        contextStore: dependencies.contextStore,
        planStore: dependencies.personalActionPlanStore,
      };
      if (request.method === "GET") {
        const result = await readPersonalActionPlan(
          request.headers.authorization,
          planDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
        return;
      }
      try {
        const result = await savePersonalActionPlan(
          request.headers.authorization,
          await readJsonBody(request),
          planDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    if (request.method === "PATCH" && relationshipMatch !== null) {
      if (dependencies.promotionTargetStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "promotion_targets_unavailable"},
        }));
        return;
      }
      try {
        const result = await updatePromotionTargetRelationship(
          request.headers.authorization,
          relationshipMatch[1] ?? "",
          await readJsonBody(request),
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            targetStore: dependencies.promotionTargetStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    if (
      request.method === "PUT" &&
      requestUrl.pathname === "/v1/promotion-target-stage-aliases"
    ) {
      if (dependencies.promotionTargetStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "promotion_targets_unavailable"},
        }));
        return;
      }
      try {
        const result = await configurePromotionTargetStageAliases(
          request.headers.authorization,
          await readJsonBody(request),
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            targetStore: dependencies.promotionTargetStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    if (
      request.method === "GET" &&
      requestUrl.pathname === "/v1/questionnaire-metrics"
    ) {
      if (dependencies.questionnaireMetricCompatibilityStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "questionnaire_metric_compatibility_unavailable"},
        }));
        return;
      }
      const result = await listQuestionnaireMetricCompatibility(
        request.headers.authorization,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          compatibilityStore:
            dependencies.questionnaireMetricCompatibilityStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      request.method === "POST" &&
      requestUrl.pathname === "/v1/questionnaire-metric-decisions"
    ) {
      if (dependencies.questionnaireMetricCompatibilityStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "questionnaire_metric_compatibility_unavailable"},
        }));
        return;
      }
      try {
        const result = await recordQuestionnaireMetricCompatibility(
          request.headers.authorization,
          await readJsonBody(request),
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            compatibilityStore:
              dependencies.questionnaireMetricCompatibilityStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    const metricRevocationMatch =
      /^\/v1\/questionnaire-metric-decisions\/([^/]+)\/revoke$/
        .exec(requestUrl.pathname);
    if (request.method === "POST" && metricRevocationMatch !== null) {
      if (dependencies.questionnaireMetricCompatibilityStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "questionnaire_metric_compatibility_unavailable"},
        }));
        return;
      }
      const eventId = metricRevocationMatch[1];
      if (eventId === undefined) {
        response.statusCode = 404;
        response.end(JSON.stringify({error: {code: "not_found"}}));
        return;
      }
      try {
        const result = await revokeQuestionnaireMetricCompatibility(
          request.headers.authorization,
          eventId,
          await readJsonBody(request),
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            compatibilityStore:
              dependencies.questionnaireMetricCompatibilityStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    if (
      request.method === "GET" &&
      requestUrl.pathname === "/v1/questionnaire-administration"
    ) {
      if (dependencies.questionnaireAdministrationStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: { code: "questionnaire_administration_unavailable" },
        }));
        return;
      }
      const result = await listQuestionnaireAdministration(
        request.headers.authorization,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          administrationStore: dependencies.questionnaireAdministrationStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      request.method === "POST" &&
      requestUrl.pathname === "/v1/questionnaire-drafts"
    ) {
      if (dependencies.questionnaireAdministrationStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: { code: "questionnaire_administration_unavailable" },
        }));
        return;
      }
      try {
        const body = await readJsonBody(request);
        const result = await createQuestionnaireDraft(
          request.headers.authorization,
          body,
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            administrationStore:
              dependencies.questionnaireAdministrationStore,
          },
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    const draftMatch = /^\/v1\/questionnaire-drafts\/([^/]+)$/.exec(
      requestUrl.pathname,
    );
    const publishMatch =
      /^\/v1\/questionnaire-drafts\/([^/]+)\/publish$/.exec(
        requestUrl.pathname,
      );
    if (
      (draftMatch !== null || publishMatch !== null) &&
      (request.method === "GET" ||
        request.method === "PUT" ||
        request.method === "POST")
    ) {
      if (dependencies.questionnaireAdministrationStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: { code: "questionnaire_administration_unavailable" },
        }));
        return;
      }
      const draftId = (publishMatch ?? draftMatch)?.[1];
      if (draftId === undefined) {
        response.statusCode = 404;
        response.end(JSON.stringify({ error: { code: "not_found" } }));
        return;
      }
      const administrationDependencies = {
        identityVerifier: dependencies.identityVerifier,
        contextStore: dependencies.contextStore,
        administrationStore: dependencies.questionnaireAdministrationStore,
      };
      try {
        const result = request.method === "GET" && draftMatch !== null
          ? await readQuestionnaireDraft(
            request.headers.authorization,
            draftId,
            administrationDependencies,
          )
          : request.method === "PUT" && draftMatch !== null
          ? await updateQuestionnaireDraft(
            request.headers.authorization,
            draftId,
            await readJsonBody(request),
            administrationDependencies,
          )
          : request.method === "POST" && publishMatch !== null
          ? await publishQuestionnaireDraft(
            request.headers.authorization,
            draftId,
            await readJsonBody(request),
            administrationDependencies,
          )
          : { status: 404, body: { error: { code: "not_found" } } };
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    const questionnaireMatch = /^\/v1\/questionnaire-versions\/([^/]+)$/
      .exec(requestUrl.pathname);
    if (request.method === "GET" && questionnaireMatch !== null) {
      if (dependencies.questionnaireStore === undefined) {
        response.statusCode = 503;
        response.end(
          JSON.stringify({ error: { code: "questionnaire_unavailable" } }),
        );
        return;
      }
      const versionId = questionnaireMatch[1];
      if (versionId === undefined) {
        response.statusCode = 404;
        response.end(JSON.stringify({ error: { code: "not_found" } }));
        return;
      }
      const result = await readPublishedQuestionnaire(
        request.headers.authorization,
        versionId,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          questionnaireStore: dependencies.questionnaireStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }
    if (
      request.method === "GET" &&
      requestUrl.pathname === "/v1/sync/changes"
    ) {
      if (dependencies.commandStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({ error: { code: "sync_unavailable" } }));
        return;
      }
      const result = await handleSyncChanges(
        request.headers.authorization,
        requestUrl.searchParams,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          commandStore: dependencies.commandStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      request.method === "GET" &&
      request.url === "/v1/session/context"
    ) {
      const result = await getSessionContext(
        request.headers.authorization,
        dependencies,
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    response.statusCode = 404;
    response.end(JSON.stringify({ error: { code: "not_found" } }));
  });
}

class PayloadTooLargeError extends Error {}

function writeBodyError(
  response: {statusCode: number; end(value: string): void},
  error: unknown,
): void {
  response.statusCode = error instanceof PayloadTooLargeError ? 413 : 400;
  response.end(JSON.stringify({
    error: {
      code: error instanceof PayloadTooLargeError
        ? "payload_too_large"
        : "invalid_json",
    },
  }));
}

async function readJsonBody(request: AsyncIterable<unknown>): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk));
    size += buffer.length;
    if (size > 1024 * 1024) {
      throw new PayloadTooLargeError();
    }
    chunks.push(buffer);
  }
  if (chunks.length === 0) {
    throw new SyntaxError("Request body is empty");
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
}
