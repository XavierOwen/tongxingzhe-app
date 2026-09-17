import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = readFileSync(
  fileURLToPath(new URL("../../src/main.ts", import.meta.url)),
  "utf8",
);
const productionServer = readFileSync(
  fileURLToPath(new URL("../../src/server.ts", import.meta.url)),
  "utf8",
);
const assignmentModule = readFileSync(
  fileURLToPath(
    new URL("../../src/organization-project-membership-assignment.ts", import.meta.url),
  ),
  "utf8",
);

test("production composition wires assignment through the shared pool and generic verifier", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationProjectMembershipAssignmentStore.*organization-project-membership-assignment\.js/s,
  );
  assert.match(
    productionMain,
    /new PostgresOrganizationProjectMembershipAssignmentStore\(query\)/,
  );
  assert.match(
    productionMain,
    /organizationProjectMembershipAssignmentStore,/,
  );
  assert.match(
    productionMain,
    /const identityVerifier = createProductionIdentityVerifier\(/,
  );
  assert.match(
    productionMain,
    /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/,
  );
  assert.match(
    productionServer,
    /handleOrganizationProjectMembershipAssignment/,
  );
  assert.match(
    productionServer,
    /organizationProjectMembershipAssignmentStore/,
  );
  assert.match(
    productionServer,
    /matchOrganizationProjectMembershipAssignmentRequestTarget/,
  );
});

test("assignment wiring has no extra pool, Auth lookup, or context gate", () => {
  const storeWiringStart = productionMain.indexOf(
    "const organizationProjectMembershipAssignmentStore",
  );
  const nextStoreStart = productionMain.indexOf(
    "const organizationMembershipSelfLeaveStore",
    storeWiringStart,
  );
  const serverConstructionStart = productionMain.indexOf(
    "const server = createBackendServer",
  );
  assert.ok(storeWiringStart >= 0);
  assert.ok(nextStoreStart > storeWiringStart);
  assert.ok(serverConstructionStart > storeWiringStart);
  const assignmentWiring = productionMain.slice(
    storeWiringStart,
    nextStoreStart,
  );

  assert.doesNotMatch(
    assignmentWiring,
    /new\s+Pool|DATABASE_URL|createSupabaseAuthUserLookup|AuthUser|SessionContext|organizationCreationIdentityVerifier|BEGIN|COMMIT/i,
  );
  assert.doesNotMatch(
    `${assignmentModule}\n${assignmentWiring}`,
    /console\.|process\.(?:stdout|stderr)|\blogger\b/,
  );
});

test("assignment bridge is one parameterized app_data call with six values and no private prelookup", () => {
  const queryCalls = assignmentModule.match(/\.query\(/g) ?? [];
  assert.equal(queryCalls.length, 1);
  assert.match(
    assignmentModule,
    /app_data\.assign_organization_project_member_for_identity_v1/,
  );
  assert.match(
    assignmentModule,
    /\$1::text[\s\S]*\$2::text[\s\S]*\$3::uuid[\s\S]*\$4::uuid[\s\S]*\$5::uuid[\s\S]*\$6::uuid/,
  );
  assert.doesNotMatch(assignmentModule, /app_private/);

  const queryLiteral = assignmentModule.match(/this\.query\(\s*`([\s\S]*?)`,/);
  assert.ok(queryLiteral?.[1]);
  assert.doesNotMatch(queryLiteral[1], /JOIN|UNION/i);
});

test("assignment raw dispatch precedes WHATWG URL normalization and awaits the handler", () => {
  const rawMatcher = productionServer.indexOf(
    "matchOrganizationProjectMembershipAssignmentRequestTarget",
  );
  const requestUrl = productionServer.indexOf("const requestUrl = new URL");
  assert.ok(rawMatcher >= 0);
  assert.ok(requestUrl > rawMatcher);

  const route = productionServer.slice(rawMatcher, requestUrl);
  assert.match(route, /request\.method === "POST"/);
  assert.match(
    route,
    /const result = await handleOrganizationProjectMembershipAssignment\(/,
  );
  assert.match(route, /readBody: async \(\) => readJsonBody\(request\)/);
  assert.match(route, /catch \(error\) \{[\s\S]*writeBodyError\(response, error\)/);
  assert.doesNotMatch(route, /new URL\(/);
});
