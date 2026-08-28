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
import {
  readPersonalActionReminder,
  savePersonalActionReminder,
  type PersonalActionReminderStore,
} from "./personal-action-reminders.js";
import {
  readPersonalCurrentRelationshipStage,
  type PersonalCurrentRelationshipStageStore,
} from "./personal-current-relationship-stage.js";
import {
  readPersonalFollowUpConsentRatio,
  type PersonalFollowUpConsentRatioStore,
} from "./personal-follow-up-consent-ratio.js";
import {
  readPersonalRelationshipStageChangeSummary,
  type PersonalRelationshipStageChangeSummaryStore,
} from "./personal-relationship-stage-change-summary.js";
import {
  handlePersonalFollowUpConsentOptIn,
  type PersonalFollowUpConsentOptInStore,
} from "./personal-follow-up-consent-opt-in.js";
import {
  readManagementReportSnapshot,
  type ManagementReportSnapshotStore,
} from "./management-report-snapshots.js";
import {
  readManagementCurrentCityReportSnapshot,
  type ManagementCurrentCityReportSnapshotStore,
} from "./management-current-city-report-snapshots.js";
import {
  readManagementInterestReportSnapshot,
  type ManagementInterestReportSnapshotStore,
} from "./management-interest-report-snapshots.js";
import {
  readManagementOriginalRegionReportSnapshot,
  type ManagementOriginalRegionReportSnapshotStore,
} from "./management-original-region-report-snapshots.js";
import {
  readManagementFollowUpConsentRatioReportSnapshot,
  type ManagementFollowUpConsentRatioReportSnapshotStore,
} from "./management-follow-up-consent-ratio-report-snapshots.js";
import {
  listManagementFollowUpConsentRatioSnapshotDirectory,
  type ManagementFollowUpConsentRatioSnapshotDirectoryStore,
} from "./management-follow-up-consent-ratio-snapshot-directory.js";
import {
  listManagementOriginalRegionReportSnapshotDirectory,
  type ManagementOriginalRegionReportSnapshotDirectoryStore,
} from "./management-original-region-report-snapshot-directory.js";
import {
  exportManagementReportSnapshot,
  type ManagementReportSnapshotExportStore,
} from "./management-report-snapshot-exports.js";
import {
  listManagementReportSnapshotDirectory,
  type ManagementReportSnapshotDirectoryStore,
} from "./management-report-snapshot-directory.js";
import {
  listManagementCurrentCityReportSnapshotDirectory,
  type ManagementCurrentCityReportSnapshotDirectoryStore,
} from "./management-current-city-report-snapshot-directory.js";
import {
  listManagementInterestReportSnapshotDirectory,
  type ManagementInterestReportSnapshotDirectoryStore,
} from "./management-interest-report-snapshot-directory.js";
import {
  releaseManagementReportSnapshot,
  type ManagementReportReleaseStore,
} from "./management-report-release.js";
import {
  authenticateManagementAnalysisContext,
  loadManagementAnalysisContextForIdentity,
  selectManagementAnalysisContextForIdentity,
  type ManagementAnalysisContextStore,
} from "./management-analysis-contexts.js";

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
  readonly personalActionReminderStore?: PersonalActionReminderStore;
  readonly personalCurrentRelationshipStageStore?:
    PersonalCurrentRelationshipStageStore;
  readonly personalFollowUpConsentRatioStore?:
    PersonalFollowUpConsentRatioStore;
  readonly personalRelationshipStageChangeSummaryStore?:
    PersonalRelationshipStageChangeSummaryStore;
  readonly personalFollowUpConsentOptInStore?:
    PersonalFollowUpConsentOptInStore;
  readonly managementReportSnapshotStore?: ManagementReportSnapshotStore;
  readonly managementCurrentCityReportSnapshotStore?:
    ManagementCurrentCityReportSnapshotStore;
  readonly managementInterestReportSnapshotStore?:
    ManagementInterestReportSnapshotStore;
  readonly managementOriginalRegionReportSnapshotStore?:
    ManagementOriginalRegionReportSnapshotStore;
  readonly managementFollowUpConsentRatioReportSnapshotStore?:
    ManagementFollowUpConsentRatioReportSnapshotStore;
  readonly managementFollowUpConsentRatioSnapshotDirectoryStore?:
    ManagementFollowUpConsentRatioSnapshotDirectoryStore;
  readonly managementOriginalRegionReportSnapshotDirectoryStore?:
    ManagementOriginalRegionReportSnapshotDirectoryStore;
  readonly managementReportSnapshotExportStore?:
    ManagementReportSnapshotExportStore;
  readonly managementReportSnapshotDirectoryStore?:
    ManagementReportSnapshotDirectoryStore;
  readonly managementCurrentCityReportSnapshotDirectoryStore?:
    ManagementCurrentCityReportSnapshotDirectoryStore;
  readonly managementInterestReportSnapshotDirectoryStore?:
    ManagementInterestReportSnapshotDirectoryStore;
  readonly managementReportReleaseStore?: ManagementReportReleaseStore;
  readonly managementAnalysisContextStore?: ManagementAnalysisContextStore;
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

    if (
      requestUrl.pathname === "/v1/management-analysis/context" &&
      (request.method === "GET" || request.method === "PUT")
    ) {
      const authentication = await authenticateManagementAnalysisContext(
        request.headers.authorization,
        dependencies.identityVerifier,
      );
      if (authentication.status === "rejected") {
        response.statusCode = authentication.result.status;
        response.end(JSON.stringify(authentication.result.body));
        return;
      }
      if (
        requestUrl.search.length > 0 ||
        (request.method === "GET" && requestDeclaresBody(request.headers))
      ) {
        response.statusCode = 400;
        response.end(JSON.stringify({
          error: {code: "invalid_management_analysis_context"},
        }));
        return;
      }
      if (dependencies.managementAnalysisContextStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "management_analysis_context_unavailable"},
        }));
        return;
      }
      if (request.method === "GET") {
        const result = await loadManagementAnalysisContextForIdentity(
          authentication.identity,
          dependencies.managementAnalysisContextStore,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
        return;
      }
      try {
        const body = await readJsonBody(request);
        const result = await selectManagementAnalysisContextForIdentity(
          authentication.identity,
          body,
          dependencies.managementAnalysisContextStore,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
      } catch (error) {
        writeBodyError(response, error);
      }
      return;
    }

    const managementReportSnapshotDirectoryMatch = requestUrl.pathname.match(
      /^\/v1\/projects\/([^/]+)\/management-report-snapshots$/,
    );
    if (
      request.method === "POST" &&
      managementReportSnapshotDirectoryMatch !== null
    ) {
      try {
        const result = await releaseManagementReportSnapshot(
          {
            authorization: request.headers.authorization,
            projectId: managementReportSnapshotDirectoryMatch[1] ?? "",
            hasQuery: requestUrl.search.length > 0,
            // The release handler authenticates before invoking this callback.
            readBody: async () => readJsonBody(request),
          },
          {
            identityVerifier: dependencies.identityVerifier,
            releaseStore: dependencies.managementReportReleaseStore,
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
      managementReportSnapshotDirectoryMatch !== null
    ) {
      const result = await listManagementReportSnapshotDirectory(
        {
          authorization: request.headers.authorization,
          projectId: managementReportSnapshotDirectoryMatch[1] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          directoryStore: dependencies.managementReportSnapshotDirectoryStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementCurrentCityReportSnapshotDirectoryMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-current-city-report-snapshots$/,
      );
    if (
      request.method === "GET" &&
      managementCurrentCityReportSnapshotDirectoryMatch !== null
    ) {
      const result = await listManagementCurrentCityReportSnapshotDirectory(
        {
          authorization: request.headers.authorization,
          projectId:
            managementCurrentCityReportSnapshotDirectoryMatch[1] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementCurrentCityReportSnapshotDirectoryStore === undefined
            ? {}
            : {
              directoryStore:
                dependencies.managementCurrentCityReportSnapshotDirectoryStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementReportSnapshotExportMatch = requestUrl.pathname.match(
      /^\/v1\/projects\/([^/]+)\/management-report-snapshots\/([^/]+)\/export$/,
    );
    if (
      request.method === "GET" &&
      managementReportSnapshotExportMatch !== null
    ) {
      const result = await exportManagementReportSnapshot(
        {
          authorization: request.headers.authorization,
          projectId: managementReportSnapshotExportMatch[1] ?? "",
          snapshotId: managementReportSnapshotExportMatch[2] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementReportSnapshotExportStore === undefined
            ? {}
            : {
              exportStore: dependencies.managementReportSnapshotExportStore,
            }),
        },
      );
      response.statusCode = result.status;
      if ("content" in result) {
        response.setHeader("content-type", "application/json; charset=utf-8");
        response.setHeader(
          "content-disposition",
          'attachment; filename="management-report-snapshot-v1.json"',
        );
        response.setHeader("x-content-type-options", "nosniff");
        response.setHeader(
          "x-management-report-export-event-id",
          result.exportEventId,
        );
        response.setHeader("content-length", Buffer.byteLength(result.content));
        response.end(result.content);
      } else {
        response.end(JSON.stringify(result.body));
      }
      return;
    }

    const managementCurrentCityReportSnapshotMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-current-city-report-snapshots\/([^/]+)$/,
      );
    if (
      request.method === "GET" &&
      managementCurrentCityReportSnapshotMatch !== null
    ) {
      const result = await readManagementCurrentCityReportSnapshot(
        {
          authorization: request.headers.authorization,
          projectId: managementCurrentCityReportSnapshotMatch[1] ?? "",
          snapshotId: managementCurrentCityReportSnapshotMatch[2] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementCurrentCityReportSnapshotStore === undefined
            ? {}
            : {
              snapshotStore:
                dependencies.managementCurrentCityReportSnapshotStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementInterestReportSnapshotDirectoryMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-interest-report-snapshots$/,
      );
    if (
      request.method === "GET" &&
      managementInterestReportSnapshotDirectoryMatch !== null
    ) {
      const result = await listManagementInterestReportSnapshotDirectory(
        {
          authorization: request.headers.authorization,
          projectId: managementInterestReportSnapshotDirectoryMatch[1] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementInterestReportSnapshotDirectoryStore === undefined
            ? {}
            : {
              directoryStore:
                dependencies.managementInterestReportSnapshotDirectoryStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementInterestReportSnapshotMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-interest-report-snapshots\/([^/]+)$/,
      );
    if (
      request.method === "GET" &&
      managementInterestReportSnapshotMatch !== null
    ) {
      const result = await readManagementInterestReportSnapshot(
        {
          authorization: request.headers.authorization,
          projectId: managementInterestReportSnapshotMatch[1] ?? "",
          snapshotId: managementInterestReportSnapshotMatch[2] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementInterestReportSnapshotStore === undefined
            ? {}
            : {
              snapshotStore:
                dependencies.managementInterestReportSnapshotStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementOriginalRegionReportSnapshotDirectoryMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-original-region-report-snapshots$/,
      );
    if (
      request.method === "GET" &&
      managementOriginalRegionReportSnapshotDirectoryMatch !== null
    ) {
      const result = await listManagementOriginalRegionReportSnapshotDirectory(
        {
          authorization: request.headers.authorization,
          projectId:
            managementOriginalRegionReportSnapshotDirectoryMatch[1] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementOriginalRegionReportSnapshotDirectoryStore === undefined
            ? {}
            : {
              directoryStore:
                dependencies.managementOriginalRegionReportSnapshotDirectoryStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementOriginalRegionReportSnapshotMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-original-region-report-snapshots\/([^/]+)$/,
      );
    if (
      request.method === "GET" &&
      managementOriginalRegionReportSnapshotMatch !== null
    ) {
      const result = await readManagementOriginalRegionReportSnapshot(
        {
          authorization: request.headers.authorization,
          projectId: managementOriginalRegionReportSnapshotMatch[1] ?? "",
          snapshotId: managementOriginalRegionReportSnapshotMatch[2] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementOriginalRegionReportSnapshotStore === undefined
            ? {}
            : {
              snapshotStore:
                dependencies.managementOriginalRegionReportSnapshotStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementFollowUpConsentRatioSnapshotDirectoryMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-follow-up-consent-ratio-report-snapshots$/,
      );
    if (
      request.method === "GET" &&
      managementFollowUpConsentRatioSnapshotDirectoryMatch !== null
    ) {
      const result = await listManagementFollowUpConsentRatioSnapshotDirectory(
        {
          authorization: request.headers.authorization,
          projectId:
            managementFollowUpConsentRatioSnapshotDirectoryMatch[1] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementFollowUpConsentRatioSnapshotDirectoryStore === undefined
            ? {}
            : {
              directoryStore:
                dependencies.managementFollowUpConsentRatioSnapshotDirectoryStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementFollowUpConsentRatioReportSnapshotMatch =
      requestUrl.pathname.match(
        /^\/v1\/projects\/([^/]+)\/management-follow-up-consent-ratio-report-snapshots\/([^/]+)$/,
      );
    if (
      request.method === "GET" &&
      managementFollowUpConsentRatioReportSnapshotMatch !== null
    ) {
      const result = await readManagementFollowUpConsentRatioReportSnapshot(
        {
          authorization: request.headers.authorization,
          projectId:
            managementFollowUpConsentRatioReportSnapshotMatch[1] ?? "",
          snapshotId:
            managementFollowUpConsentRatioReportSnapshotMatch[2] ?? "",
          hasQuery: requestUrl.search.length > 0,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.managementFollowUpConsentRatioReportSnapshotStore === undefined
            ? {}
            : {
              snapshotStore:
                dependencies.managementFollowUpConsentRatioReportSnapshotStore,
            }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    const managementReportSnapshotMatch = requestUrl.pathname.match(
      /^\/v1\/projects\/([^/]+)\/management-report-snapshots\/([^/]+)$/,
    );
    if (
      request.method === "GET" &&
      managementReportSnapshotMatch !== null
    ) {
      if (requestUrl.search.length > 0) {
        response.statusCode = 400;
        response.end(JSON.stringify({
          error: {code: "invalid_management_report_snapshot_request"},
        }));
        return;
      }
      if (dependencies.managementReportSnapshotStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "management_report_snapshot_unavailable"},
        }));
        return;
      }
      const result = await readManagementReportSnapshot(
        request.headers.authorization,
        managementReportSnapshotMatch[1] ?? "",
        managementReportSnapshotMatch[2] ?? "",
        {
          identityVerifier: dependencies.identityVerifier,
          snapshotStore: dependencies.managementReportSnapshotStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
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
        writeBodyError(response, error);
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
        writeBodyError(response, error);
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
        writeBodyError(response, error);
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
        writeBodyError(response, error);
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

    if (
      requestUrl.pathname === "/v1/personal-action-reminder" &&
      (request.method === "GET" || request.method === "PUT")
    ) {
      if (dependencies.personalActionReminderStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "personal_action_reminder_unavailable"},
        }));
        return;
      }
      const reminderDependencies = {
        identityVerifier: dependencies.identityVerifier,
        contextStore: dependencies.contextStore,
        reminderStore: dependencies.personalActionReminderStore,
      };
      if (request.method === "GET") {
        const result = await readPersonalActionReminder(
          request.headers.authorization,
          reminderDependencies,
        );
        response.statusCode = result.status;
        response.end(JSON.stringify(result.body));
        return;
      }
      try {
        const result = await savePersonalActionReminder(
          request.headers.authorization,
          await readJsonBody(request),
          reminderDependencies,
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
      requestUrl.pathname === "/v1/personal/current-relationship-stage"
    ) {
      if (
        requestUrl.search.length > 0 ||
        requestDeclaresBody(request.headers)
      ) {
        response.statusCode = 400;
        response.end(JSON.stringify({
          error: {
            code: "invalid_personal_current_relationship_stage_request",
          },
        }));
        return;
      }
      if (dependencies.personalCurrentRelationshipStageStore === undefined) {
        response.statusCode = 503;
        response.end(JSON.stringify({
          error: {code: "personal_current_relationship_stage_unavailable"},
        }));
        return;
      }
      const result = await readPersonalCurrentRelationshipStage(
        request.headers.authorization,
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          snapshotStore: dependencies.personalCurrentRelationshipStageStore,
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      request.method === "GET" &&
      requestUrl.pathname ===
        "/v1/personal/relationship-stage-change-summary"
    ) {
      const result = await readPersonalRelationshipStageChangeSummary(
        {
          authorization: request.headers.authorization,
          query: requestUrl.searchParams,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          ...(dependencies.personalRelationshipStageChangeSummaryStore ===
            undefined
            ? {}
            : {
                summaryStore:
                  dependencies.personalRelationshipStageChangeSummaryStore,
              }),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      request.method === "GET" &&
      requestUrl.pathname === "/v1/personal/follow-up-consent-ratio"
    ) {
      const result = await readPersonalFollowUpConsentRatio(
        {
          authorization: request.headers.authorization,
          query: requestUrl.searchParams,
          hasBody: requestDeclaresBody(request.headers),
        },
        {
          identityVerifier: dependencies.identityVerifier,
          contextStore: dependencies.contextStore,
          ...(dependencies.personalFollowUpConsentRatioStore === undefined
            ? {}
            : {ratioStore: dependencies.personalFollowUpConsentRatioStore}),
        },
      );
      response.statusCode = result.status;
      response.end(JSON.stringify(result.body));
      return;
    }

    if (
      (request.method === "GET" || request.method === "PUT") &&
      requestUrl.pathname ===
        "/v1/personal/follow-up-consent-ratio/opt-in"
    ) {
      try {
        const result = await handlePersonalFollowUpConsentOptIn(
          {
            method: request.method,
            authorization: request.headers.authorization,
            hasQuery: requestUrl.search.length > 0,
            hasBody: requestDeclaresBody(request.headers),
            readBody: async () => readJsonBody(request),
          },
          {
            identityVerifier: dependencies.identityVerifier,
            contextStore: dependencies.contextStore,
            ...(dependencies.personalFollowUpConsentOptInStore === undefined
              ? {}
              : {optInStore: dependencies.personalFollowUpConsentOptInStore}),
          },
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

function requestDeclaresBody(
  headers: Readonly<Record<string, string | string[] | undefined>>,
): boolean {
  return headers["transfer-encoding"] !== undefined ||
    (headers["content-length"] !== undefined &&
      headers["content-length"] !== "0");
}

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
