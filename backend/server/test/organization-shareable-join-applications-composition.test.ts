import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const main = source("../../src/main.ts");
const server = source("../../src/server.ts");
const applicationModule = source(
  "../../src/organization-shareable-join-applications.ts",
);
const runner = source("../../../../tool/run_postgres_tests_in_docker.sh");

test("production wires applications through generic identity and pool query", () => {
  assert.match(main,
    /PostgresOrganizationShareableJoinApplicationStore.*organization-shareable-join-applications\.js/s);
  assert.match(main, /new PostgresOrganizationShareableJoinApplicationStore\(query\)/);
  assert.match(main, /organizationShareableJoinApplicationStore,/);
  assert.match(server, /handleOrganizationShareableJoinApplication/);
  assert.match(server,
    /applicationStore:\s*dependencies\.organizationShareableJoinApplicationStore/);
  assert.match(applicationModule, /IdentityVerifier/);
  assert.match(applicationModule,
    /app_data\.submit_organization_shareable_join_application_for_identity_v1/);
  assert.match(applicationModule,
    /app_data\.approve_organization_shareable_join_application_for_identity_v1/);
  assert.doesNotMatch(applicationModule,
    /OrganizationCreation|AuthUser|SessionContext|app_private|SUPABASE_PUBLISHABLE_KEY/);
});

test("raw application targets are matched before WHATWG normalization", () => {
  const raw = server.indexOf(
    "matchOrganizationShareableJoinApplicationRequestTarget",
  );
  const normalized = server.indexOf("new URL(");
  assert.ok(raw >= 0);
  assert.ok(normalized > raw);
  assert.match(server.slice(raw, normalized), /request\.method === "POST"/);
});

test("Docker runtime integration receives both application fixtures", () => {
  assert.match(runner,
    /ORGANIZATION_SHAREABLE_JOIN_APPLICATION_SUBMIT_FIXTURE=\/source\/backend\/database\/fixtures\/0093_organization_shareable_join_application_submit\.sql/);
  assert.match(runner,
    /ORGANIZATION_SHAREABLE_JOIN_APPLICATION_APPROVAL_FIXTURE=\/source\/backend\/database\/fixtures\/0094_organization_shareable_join_application_approval\.sql/);
  assert.match(runner,
    /dist\/test\/organization-shareable-join-applications\.integration\.js/);
});

function source(relativePath: string): string {
  return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), "utf8");
}
