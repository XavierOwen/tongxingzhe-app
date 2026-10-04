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
  fileURLToPath(
    new URL("../../src/organization-deletion-recovery-directory.ts", import.meta.url),
  ),
  "utf8",
);

test("production composition wires the recovery reader to verified identity and pool query", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationDeletionRecoveryDirectoryStore,[\s\S]+from "\.\/organization-deletion-recovery-directory\.js"/,
  );
  assert.match(
    productionMain,
    /const organizationDeletionRecoveryDirectoryStore =\s*\n\s*new PostgresOrganizationDeletionRecoveryDirectoryStore\(query\)/,
  );
  assert.match(productionMain, /organizationDeletionRecoveryDirectoryStore,/);
  assert.match(productionMain, /const identityVerifier = createProductionIdentityVerifier\(/);
  assert.match(
    productionMain,
    /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/,
  );
  const start = productionMain.indexOf("const organizationDeletionRecoveryDirectoryStore");
  const server = productionMain.indexOf("const server = createBackendServer");
  assert.ok(start >= 0 && server > start);
  assert.doesNotMatch(
    productionMain.slice(start, server),
    /OrganizationCreationIdentity|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/,
  );
});

test("server keeps exact GET under the raw path guard and passes only verified identity dependencies", () => {
  const rawGuard = productionServer.indexOf(
    "requestUrl.pathname !== (request.url ?? \"/\").split(\"?\")[0]",
  );
  const route = productionServer.indexOf(
    "requestUrl.pathname === \"/v1/organizations/deletion-recovery\"",
    rawGuard,
  );
  assert.ok(rawGuard >= 0 && route > rawGuard);
  const routeStart = productionServer.lastIndexOf("if (", route);
  const routeBody = productionServer.slice(routeStart, route + 1_100);
  assert.match(routeBody, /request\.method === "GET"/);
  assert.match(routeBody, /identityVerifier: dependencies\.identityVerifier/);
  assert.match(routeBody, /request\.url \?\? ""\)\.includes\("\?"\)/);
  assert.match(routeBody, /requestDeclaresBody\(request\.headers\)/);
  assert.doesNotMatch(routeBody, /actor|userId|readJsonBody/);
});

test("recovery store calls only the approved SQL reader and keeps complete SQL order", () => {
  assert.match(
    directoryModule,
    /app_data\.list_organization_deletion_recovery_for_identity_v1\(\$1::text, \$2::text\)/,
  );
  assert.doesNotMatch(directoryModule, /\.sort\(|localeCompare|\bLIMIT\b|\bOFFSET\b/i);
  assert.doesNotMatch(directoryModule, /INSERT|UPDATE|DELETE|app_private|console\.|process\./);
});
