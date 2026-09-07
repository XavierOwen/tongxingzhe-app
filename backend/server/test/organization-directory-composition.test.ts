import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const productionMain = readFileSync(
  fileURLToPath(new URL("../../src/main.ts", import.meta.url)),
  "utf8",
);
const productionServer = readFileSync(
  fileURLToPath(new URL("../../src/server.ts", import.meta.url)),
  "utf8",
);
const directoryModule = readFileSync(
  fileURLToPath(new URL("../../src/organization-directory.ts", import.meta.url)),
  "utf8",
);
const dockerRunner = readFileSync(
  fileURLToPath(
    new URL("../../../../tool/run_postgres_tests_in_docker.sh", import.meta.url),
  ),
  "utf8",
);

test("production composition wires the directory to generic identity and pool query", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationDirectoryStore.*organization-directory\.js/,
  );
  assert.match(
    productionMain,
    /const organizationDirectoryStore = new PostgresOrganizationDirectoryStore\(query\)/,
  );
  assert.match(productionMain, /organizationDirectoryStore,/);
  assert.match(
    productionMain,
    /const identityVerifier = createProductionIdentityVerifier\(/,
  );
  assert.match(
    productionMain,
    /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/,
  );

  const directoryWiringStart = productionMain.indexOf(
    "const organizationDirectoryStore",
  );
  const serverStart = productionMain.indexOf("const server = createBackendServer");
  assert.ok(directoryWiringStart >= 0);
  assert.ok(serverStart > directoryWiringStart);
  assert.doesNotMatch(
    productionMain.slice(directoryWiringStart, serverStart),
    /OrganizationCreationIdentity|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/,
  );
});

test("server keeps raw-path rejection ahead of the literal GET directory route", () => {
  const rawGuard = productionServer.indexOf(
    "requestUrl.pathname !== (request.url ?? \"/\").split(\"?\")[0]",
  );
  const directoryRoute = productionServer.indexOf(
    "requestUrl.pathname === \"/v1/organizations\"",
    rawGuard,
  );
  assert.ok(rawGuard >= 0);
  assert.ok(directoryRoute > rawGuard);
  assert.match(
    productionServer.slice(rawGuard, directoryRoute + 80),
    /request\.method === "GET"/,
  );
  assert.match(
    productionServer.slice(directoryRoute, directoryRoute + 900),
    /identityVerifier: dependencies\.identityVerifier/,
  );
  assert.match(
    productionServer.slice(directoryRoute, directoryRoute + 900),
    /request\.url \?\? ""\)\.includes\("\?"\)/,
  );
  assert.match(
    productionServer.slice(directoryRoute, directoryRoute + 900),
    /requestDeclaresBody\(request\.headers\)/,
  );
  assert.doesNotMatch(
    productionServer.slice(directoryRoute, directoryRoute + 900),
    /readJsonBody/,
  );
});

test("directory module stays independent of creation eligibility and project context", () => {
  assert.match(directoryModule, /type IdentityVerifier/);
  assert.match(
    directoryModule,
    /app_data\.list_organizations_for_identity_v1\(\$1::text, \$2::text\)/,
  );
  assert.doesNotMatch(
    directoryModule,
    /OrganizationCreation|AuthUser|SessionContext|app_private|SUPABASE_PUBLISHABLE_KEY/,
  );
  assert.doesNotMatch(directoryModule, /\.sort\(|localeCompare|\bLIMIT\b|OFFSET/i);
  assert.doesNotMatch(
    directoryModule,
    /console\.|process\.(?:stdout|stderr)|\blogger\b/,
  );
});

test("Docker runtime test receives the 0089 fixture", () => {
  assert.match(
    dockerRunner,
    /ORGANIZATION_DIRECTORY_FIXTURE=\/source\/backend\/database\/fixtures\/0089_organization_directory\.sql/,
  );
  assert.match(
    dockerRunner,
    /dist\/test\/organization-directory\.integration\.js/,
  );
});
