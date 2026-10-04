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
const lifecycleModule = readFileSync(
  fileURLToPath(new URL("../../src/organization-deletion-lifecycle.ts", import.meta.url)),
  "utf8",
);

test("production composition wires lifecycle through generic identity and the pool query", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationDeletionLifecycleStore.*organization-deletion-lifecycle\.js/s,
  );
  assert.match(
    productionMain,
    /new PostgresOrganizationDeletionLifecycleStore\(query\)/,
  );
  assert.match(productionMain, /organizationDeletionLifecycleStore,/);
  assert.match(productionMain, /const identityVerifier = createProductionIdentityVerifier\(/);
  assert.match(productionMain, /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/);
  assert.match(productionServer, /handleOrganizationDeletionLifecycle/);
  assert.match(productionServer, /organizationDeletionLifecycleStore/);
});

test("lifecycle wiring does not depend on creation eligibility or SessionContext", () => {
  const start = productionMain.indexOf("const organizationDeletionLifecycleStore");
  const serverConstruction = productionMain.indexOf("const server = createBackendServer");
  assert.ok(start >= 0);
  assert.ok(serverConstruction > start);
  const wiring = productionMain.slice(start, serverConstruction);
  assert.doesNotMatch(wiring, /OrganizationCreation|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/i);
  assert.match(lifecycleModule, /IdentityVerifier/);
  assert.doesNotMatch(lifecycleModule, /OrganizationCreation|AuthUser|SessionContext|app_private/i);
});
