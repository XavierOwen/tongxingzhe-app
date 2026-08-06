import { Pool } from "pg";

import { createProductionIdentityVerifier } from "./identity.js";
import { createBackendServer } from "./server.js";
import { PostgresSessionContextStore } from "./session-context.js";
import { PostgresSyncCommandStore } from "./sync-store.js";
import { PostgresRegionResolutionStore } from "./region-resolution.js";
import { PostgresQuestionnaireStore } from "./questionnaire-catalog.js";
import { PostgresQuestionnaireAdministrationStore } from "./questionnaire-administration.js";
import { PostgresQuestionnaireMetricCompatibilityStore } from "./questionnaire-metric-compatibility.js";
import { PostgresPromotionTargetStore } from "./promotion-targets.js";
import { PostgresTargetInstitutionRelationshipStore } from "./target-institution-relationships.js";

const databaseUrl = requireEnvironment("DATABASE_URL");
const authIssuer = requireEnvironment("AUTH_ISSUER");
const authAudience = process.env.AUTH_AUDIENCE?.trim() || "authenticated";
const port = parsePort(process.env.PORT);

const pool = new Pool({ connectionString: databaseUrl });
const identityVerifier = createProductionIdentityVerifier({
  issuer: authIssuer,
  audience: authAudience,
  ...(process.env.AUTH_JWKS_URL === undefined
    ? {}
    : { jwksUrl: process.env.AUTH_JWKS_URL }),
});
const contextStore = new PostgresSessionContextStore(async (text, values) => {
  return pool.query(text, [...values]);
});
const commandStore = new PostgresSyncCommandStore(async (text, values) => {
  return pool.query(text, [...values]);
});
const regionResolutionStore = new PostgresRegionResolutionStore(
  async (text, values) => pool.query(text, [...values]),
);
const questionnaireStore = new PostgresQuestionnaireStore(
  async (text, values) => pool.query(text, [...values]),
);
const questionnaireAdministrationStore =
  new PostgresQuestionnaireAdministrationStore(
    async (text, values) => pool.query(text, [...values]),
  );
const questionnaireMetricCompatibilityStore =
  new PostgresQuestionnaireMetricCompatibilityStore(
    async (text, values) => pool.query(text, [...values]),
  );
const promotionTargetStore = new PostgresPromotionTargetStore(
  async (text, values) => pool.query(text, [...values]),
);
const targetInstitutionRelationshipStore =
  new PostgresTargetInstitutionRelationshipStore(
    async (text, values) => pool.query(text, [...values]),
  );
const server = createBackendServer({
  identityVerifier,
  contextStore,
  commandStore,
  regionResolutionStore,
  questionnaireStore,
  questionnaireAdministrationStore,
  questionnaireMetricCompatibilityStore,
  promotionTargetStore,
  promotionTargetRetentionStore: promotionTargetStore,
  targetInstitutionRelationshipStore,
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
