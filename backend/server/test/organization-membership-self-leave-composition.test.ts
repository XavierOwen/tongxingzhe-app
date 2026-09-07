import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = source("../../src/main.ts");
const productionServer = source("../../src/server.ts");
const leaveModule = source("../../src/organization-membership-self-leave.ts");
const dockerRunner = source("../../../../tool/run_postgres_tests_in_docker.sh");

test("production composition wires self-leave through the generic identity chain", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationMembershipSelfLeaveStore.*organization-membership-self-leave\.js/s,
  );
  assert.match(
    productionMain,
    /new PostgresOrganizationMembershipSelfLeaveStore\(query\)/,
  );
  assert.match(productionMain, /organizationMembershipSelfLeaveStore,/);
  assert.match(productionMain, /const identityVerifier = createProductionIdentityVerifier\(/);
  assert.match(
    productionMain,
    /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/,
  );
  assert.match(productionServer, /handleOrganizationMembershipSelfLeave/);
  assert.match(productionServer, /organizationMembershipSelfLeaveStore/);
});

test("self-leave does not use creation eligibility, invitation email, SessionContext, or private SQL", () => {
  const wiringStart = productionMain.indexOf(
    "const organizationMembershipSelfLeaveStore",
  );
  const serverStart = productionMain.indexOf("const server = createBackendServer");
  assert.ok(wiringStart >= 0);
  assert.ok(serverStart > wiringStart);
  const wiring = productionMain.slice(wiringStart, serverStart);
  assert.doesNotMatch(
    wiring,
    /OrganizationCreation|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/i,
  );
  assert.match(leaveModule, /IdentityVerifier/);
  assert.doesNotMatch(
    leaveModule,
    /OrganizationCreation|AuthUser|SessionContext|target.*email|app_private/i,
  );
  const route = productionServer.slice(
    productionServer.indexOf("const membershipSelfLeaveMatch"),
    productionServer.indexOf("const requestUrl"),
  );
  assert.doesNotMatch(`${leaveModule}\n${route}`, /console\.|process\.(?:stdout|stderr)|\blogger\b/i);
});

test("Docker runtime test receives the 0090 self-leave fixture", () => {
  assert.match(
    dockerRunner,
    /ORGANIZATION_MEMBERSHIP_SELF_LEAVE_FIXTURE=\/source\/backend\/database\/fixtures\/0090_organization_membership_self_leave\.sql/,
  );
  assert.match(
    dockerRunner,
    /dist\/test\/organization-membership-self-leave\.integration\.js/,
  );
});

function source(relativePath: string): string {
  return readFileSync(
    fileURLToPath(new URL(relativePath, import.meta.url)),
    "utf8",
  );
}
