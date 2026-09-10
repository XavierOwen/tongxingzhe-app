import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = source("../../src/main.ts");
const productionServer = source("../../src/server.ts");
const linkModule = source("../../src/organization-shareable-join-links.ts");
const dockerRunner = source("../../../../tool/run_postgres_tests_in_docker.sh");

test("production composition wires shareable links through generic identity and pool query", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationShareableJoinLinkStore.*organization-shareable-join-links\.js/s,
  );
  assert.match(
    productionMain,
    /new PostgresOrganizationShareableJoinLinkStore\(query\)/,
  );
  assert.match(productionMain, /organizationShareableJoinLinkStore,/);
  assert.match(
    productionMain,
    /const identityVerifier = createProductionIdentityVerifier\(/,
  );
  assert.match(
    productionMain,
    /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/,
  );
  assert.match(productionServer, /handleOrganizationShareableJoinLink/);
  assert.match(
    productionServer,
    /linkStore: dependencies\.organizationShareableJoinLinkStore/,
  );
});

test("shareable link wiring excludes creation identity, context, and private access", () => {
  const wiringStart = productionMain.indexOf(
    "const organizationShareableJoinLinkStore",
  );
  const serverStart = productionMain.indexOf("const server = createBackendServer");
  assert.ok(wiringStart >= 0);
  assert.ok(serverStart > wiringStart);
  assert.doesNotMatch(
    productionMain.slice(wiringStart, serverStart),
    /OrganizationCreation|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/i,
  );
  assert.match(linkModule, /IdentityVerifier/);
  assert.match(
    linkModule,
    /app_data\.create_organization_shareable_join_link_for_identity_v1/,
  );
  assert.match(
    linkModule,
    /app_data\.preview_organization_shareable_join_link_for_identity_v1/,
  );
  assert.doesNotMatch(
    linkModule,
    /OrganizationCreation|AuthUser|SessionContext|app_private|SUPABASE_PUBLISHABLE_KEY/,
  );
  assert.doesNotMatch(
    linkModule,
    /console\.|process\.(?:stdout|stderr)|\blogger\b/,
  );
});

test("server matches shareable link targets before WHATWG normalization", () => {
  const rawMatch = productionServer.indexOf(
    "matchOrganizationShareableJoinLinkRequestTarget",
  );
  const whatwgUrl = productionServer.indexOf("new URL(");
  assert.ok(rawMatch >= 0);
  assert.ok(whatwgUrl > rawMatch);
  const route = productionServer.slice(rawMatch, whatwgUrl);
  assert.match(route, /request\.method ===/);
  assert.match(route, /requestDeclaresBody\(request\.headers\)/);
  assert.match(route, /identityVerifier: dependencies\.identityVerifier/);
});

test("Docker runtime test receives the 0092 fixture", () => {
  assert.match(
    dockerRunner,
    /ORGANIZATION_SHAREABLE_JOIN_LINK_FIXTURE=\/source\/backend\/database\/fixtures\/0092_organization_shareable_join_link\.sql/,
  );
  assert.match(
    dockerRunner,
    /dist\/test\/organization-shareable-join-links\.integration\.js/,
  );
});

function source(relativePath: string): string {
  return readFileSync(
    fileURLToPath(new URL(relativePath, import.meta.url)),
    "utf8",
  );
}
