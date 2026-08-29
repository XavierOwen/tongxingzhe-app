import { Pool } from "pg";

import { createProductionIdentityVerifier } from "./identity.js";
import {
  createOrganizationCreationIdentityVerifier,
  createSupabaseAuthUserLookup,
} from "./organization-creation-identity.js";
import { PostgresOrganizationCreationStore } from "./organization-creation.js";
import { createBackendServer } from "./server.js";
import { PostgresSessionContextStore } from "./session-context.js";
import { PostgresSyncCommandStore } from "./sync-store.js";
import { PostgresRegionResolutionStore } from "./region-resolution.js";
import { PostgresQuestionnaireStore } from "./questionnaire-catalog.js";
import { PostgresQuestionnaireAdministrationStore } from "./questionnaire-administration.js";
import { PostgresQuestionnaireMetricCompatibilityStore } from "./questionnaire-metric-compatibility.js";
import { PostgresPromotionTargetStore } from "./promotion-targets.js";
import { PostgresTargetInstitutionRelationshipStore } from "./target-institution-relationships.js";
import { PostgresPersonalActionPlanStore } from "./personal-action-plans.js";
import { PostgresPersonalActionReminderStore } from "./personal-action-reminders.js";
import {
  PostgresPersonalCurrentRelationshipStageStore,
} from "./personal-current-relationship-stage.js";
import {
  PostgresPersonalFollowUpConsentRatioStore,
} from "./personal-follow-up-consent-ratio.js";
import {
  PostgresPersonalRelationshipStageChangeSummaryStore,
} from "./personal-relationship-stage-change-summary.js";
import {
  PostgresPersonalFollowUpConsentOptInStore,
} from "./personal-follow-up-consent-opt-in.js";
import { PostgresManagementReportSnapshotStore } from "./management-report-snapshots.js";
import {
  PostgresManagementCurrentCityReportSnapshotStore,
} from "./management-current-city-report-snapshots.js";
import {
  PostgresManagementInterestReportSnapshotStore,
} from "./management-interest-report-snapshots.js";
import {
  PostgresManagementOriginalRegionReportSnapshotStore,
} from "./management-original-region-report-snapshots.js";
import {
  PostgresManagementFollowUpConsentRatioReportSnapshotStore,
} from "./management-follow-up-consent-ratio-report-snapshots.js";
import {
  PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore,
} from "./management-follow-up-consent-ratio-snapshot-directory.js";
import {
  PostgresManagementOriginalRegionReportSnapshotDirectoryStore,
} from "./management-original-region-report-snapshot-directory.js";
import {
  PostgresManagementReportSnapshotExportStore,
} from "./management-report-snapshot-exports.js";
import { PostgresManagementReportSnapshotDirectoryStore } from "./management-report-snapshot-directory.js";
import {
  PostgresManagementCurrentCityReportSnapshotDirectoryStore,
} from "./management-current-city-report-snapshot-directory.js";
import {
  PostgresManagementInterestReportSnapshotDirectoryStore,
} from "./management-interest-report-snapshot-directory.js";
import { PostgresManagementReportReleaseStore } from "./management-report-release.js";
import { PostgresManagementAnalysisContextStore } from "./management-analysis-contexts.js";

const databaseUrl = requireEnvironment("DATABASE_URL");
const authIssuer = requireEnvironment("AUTH_ISSUER");
const supabasePublishableKey = requireEnvironment("SUPABASE_PUBLISHABLE_KEY");
const authAudience = process.env.AUTH_AUDIENCE?.trim() || "authenticated";
const port = parsePort(process.env.PORT);

const pool = new Pool({ connectionString: databaseUrl });
const query = (text: string, values: readonly unknown[]) =>
  pool.query(text, [...values]);
const identityVerifier = createProductionIdentityVerifier({
  issuer: authIssuer,
  audience: authAudience,
  ...(process.env.AUTH_JWKS_URL === undefined
    ? {}
    : { jwksUrl: process.env.AUTH_JWKS_URL }),
});
const authUserEndpoint = new URL(
  "user",
  `${authIssuer.replace(/\/+$/, "")}/`,
).toString();
const organizationCreationIdentityVerifier =
  createOrganizationCreationIdentityVerifier({
    identityVerifier,
    authUserLookup: createSupabaseAuthUserLookup({
      userEndpoint: authUserEndpoint,
      publishableKey: supabasePublishableKey,
    }),
  });
const contextStore = new PostgresSessionContextStore(query);
const commandStore = new PostgresSyncCommandStore(query);
const regionResolutionStore = new PostgresRegionResolutionStore(query);
const questionnaireStore = new PostgresQuestionnaireStore(query);
const questionnaireAdministrationStore =
  new PostgresQuestionnaireAdministrationStore(query);
const questionnaireMetricCompatibilityStore =
  new PostgresQuestionnaireMetricCompatibilityStore(query);
const promotionTargetStore = new PostgresPromotionTargetStore(query);
const targetInstitutionRelationshipStore =
  new PostgresTargetInstitutionRelationshipStore(query);
const personalActionPlanStore = new PostgresPersonalActionPlanStore(query);
const personalActionReminderStore = new PostgresPersonalActionReminderStore(query);
const personalCurrentRelationshipStageStore =
  new PostgresPersonalCurrentRelationshipStageStore(query);
const personalFollowUpConsentRatioStore =
  new PostgresPersonalFollowUpConsentRatioStore(query);
const personalRelationshipStageChangeSummaryStore =
  new PostgresPersonalRelationshipStageChangeSummaryStore(query);
const personalFollowUpConsentOptInStore =
  new PostgresPersonalFollowUpConsentOptInStore(query);
// A direct pool query is intentional: PostgreSQL commits its implicit
// transaction before this promise resolves and before the HTTP response starts.
const managementReportSnapshotStore =
  new PostgresManagementReportSnapshotStore(query);
const managementCurrentCityReportSnapshotStore =
  new PostgresManagementCurrentCityReportSnapshotStore(query);
const managementInterestReportSnapshotStore =
  new PostgresManagementInterestReportSnapshotStore(query);
const managementOriginalRegionReportSnapshotStore =
  new PostgresManagementOriginalRegionReportSnapshotStore(query);
const managementFollowUpConsentRatioReportSnapshotStore =
  new PostgresManagementFollowUpConsentRatioReportSnapshotStore(query);
const managementFollowUpConsentRatioSnapshotDirectoryStore =
  new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore(query);
const managementOriginalRegionReportSnapshotDirectoryStore =
  new PostgresManagementOriginalRegionReportSnapshotDirectoryStore(query);
// The export bridge records its immutable audit in the same statement. The
// response file is serialized only after PostgreSQL confirms that commit.
const managementReportSnapshotExportStore =
  new PostgresManagementReportSnapshotExportStore(query);
const managementReportSnapshotDirectoryStore =
  new PostgresManagementReportSnapshotDirectoryStore(query);
const managementCurrentCityReportSnapshotDirectoryStore =
  new PostgresManagementCurrentCityReportSnapshotDirectoryStore(query);
const managementInterestReportSnapshotDirectoryStore =
  new PostgresManagementInterestReportSnapshotDirectoryStore(query);
// One pool query is also the transaction boundary for the trusted release.
// Awaiting it keeps the HTTP response behind PostgreSQL commit acknowledgement.
const managementReportReleaseStore = new PostgresManagementReportReleaseStore(
  query,
);
const managementAnalysisContextStore =
  new PostgresManagementAnalysisContextStore(query);
const organizationCreationStore = new PostgresOrganizationCreationStore(query);
const server = createBackendServer({
  identityVerifier,
  organizationCreationIdentityVerifier,
  organizationCreationStore,
  contextStore,
  commandStore,
  regionResolutionStore,
  questionnaireStore,
  questionnaireAdministrationStore,
  questionnaireMetricCompatibilityStore,
  promotionTargetStore,
  promotionTargetRetentionStore: promotionTargetStore,
  targetInstitutionRelationshipStore,
  personalActionPlanStore,
  personalActionReminderStore,
  personalCurrentRelationshipStageStore,
  personalFollowUpConsentRatioStore,
  personalRelationshipStageChangeSummaryStore,
  personalFollowUpConsentOptInStore,
  managementReportSnapshotStore,
  managementCurrentCityReportSnapshotStore,
  managementInterestReportSnapshotStore,
  managementOriginalRegionReportSnapshotStore,
  managementFollowUpConsentRatioReportSnapshotStore,
  managementFollowUpConsentRatioSnapshotDirectoryStore,
  managementOriginalRegionReportSnapshotDirectoryStore,
  managementReportSnapshotExportStore,
  managementReportSnapshotDirectoryStore,
  managementCurrentCityReportSnapshotDirectoryStore,
  managementInterestReportSnapshotDirectoryStore,
  managementReportReleaseStore,
  managementAnalysisContextStore,
});

server.listen(port, "0.0.0.0");

async function shutdown(): Promise<void> {
  server.close();
  await pool.end();
}

process.once("SIGINT", () => void shutdown());
process.once("SIGTERM", () => void shutdown());

function requireEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (value === undefined || value.length === 0) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function parsePort(value: string | undefined): number {
  const portValue = value?.trim() || "8080";
  const parsed = Number(portValue);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error("PORT must be an integer from 1 to 65535");
  }
  return parsed;
}
