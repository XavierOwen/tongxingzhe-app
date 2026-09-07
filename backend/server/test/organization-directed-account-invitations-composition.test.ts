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
const invitationModule = readFileSync(
  fileURLToPath(new URL(
    "../../src/organization-directed-account-invitations.ts",
    import.meta.url,
  )),
  "utf8",
);

test("production composition wires invitations through the generic identity chain", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationDirectedAccountInvitationStore.*organization-directed-account-invitations\.js/s,
  );
  assert.match(
    productionMain,
    /new PostgresOrganizationDirectedAccountInvitationStore\(query\)/,
  );
  assert.match(productionMain, /organizationDirectedAccountInvitationStore,/);
  assert.match(
    productionMain,
    /const identityVerifier = createProductionIdentityVerifier\(/,
  );
  assert.match(
    productionMain,
    /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/,
  );
  assert.match(productionServer, /handleOrganizationDirectedAccountInvitation/);
  assert.match(
    productionServer,
    /matchOrganizationDirectedAccountInvitationRequestTarget/,
  );
  assert.match(
    productionServer,
    /invitationStore: dependencies\.organizationDirectedAccountInvitationStore/,
  );
});

test("invitation composition excludes creation eligibility and private access", () => {
  const wiringStart = productionMain.indexOf(
    "const organizationDirectedAccountInvitationStore",
  );
  const serverStart = productionMain.indexOf("const server = createBackendServer");
  assert.ok(wiringStart >= 0);
  assert.ok(serverStart > wiringStart);
  const wiring = productionMain.slice(wiringStart, serverStart);

  assert.doesNotMatch(
    wiring,
    /OrganizationCreation|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/i,
  );
  assert.match(invitationModule, /IdentityVerifier/);
  assert.doesNotMatch(
    invitationModule,
    /OrganizationCreation|AuthUser|SessionContext|app_private|7A eligibility/i,
  );
  assert.doesNotMatch(
    invitationModule,
    /console\.|process\.(?:stdout|stderr)|\blogger\b/i,
  );
});

test("server matches invitation request targets before WHATWG normalization", () => {
  const rawMatch = productionServer.indexOf(
    "matchOrganizationDirectedAccountInvitationRequestTarget",
  );
  const whatwgUrl = productionServer.indexOf("new URL(");
  assert.ok(rawMatch >= 0);
  assert.ok(whatwgUrl > rawMatch);
  assert.match(
    productionServer.slice(rawMatch, whatwgUrl),
    /request\.method === "POST"/,
  );
});
