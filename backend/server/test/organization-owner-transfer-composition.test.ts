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
const transferModule = readFileSync(
  fileURLToPath(new URL("../../src/organization-owner-transfer.ts", import.meta.url)),
  "utf8",
);

test("production composition wires owner transfer through the generic identity chain", () => {
  assert.match(
    productionMain,
    /PostgresOrganizationOwnerTransferStore.*organization-owner-transfer\.js/s,
  );
  assert.match(
    productionMain,
    /new PostgresOrganizationOwnerTransferStore\(query\)/,
  );
  assert.match(productionMain, /organizationOwnerTransferStore,/);
  assert.match(productionMain, /const identityVerifier = createProductionIdentityVerifier\(/);
  assert.match(productionMain, /const query = \(text: string, values: readonly unknown\[\]\) =>\s*\n\s*pool\.query\(/);
  assert.match(productionServer, /handleOrganizationOwnerTransfer/);
  assert.match(productionServer, /organizationOwnerTransferStore/);
});

test("owner transfer composition does not use creation eligibility or SessionContext", () => {
  const transferWiringStart = productionMain.indexOf(
    "const organizationOwnerTransferStore",
  );
  const serverConstructionStart = productionMain.indexOf(
    "const server = createBackendServer",
  );
  assert.ok(transferWiringStart >= 0);
  assert.ok(serverConstructionStart > transferWiringStart);
  const transferWiring = productionMain.slice(
    transferWiringStart,
    serverConstructionStart,
  );

  assert.doesNotMatch(
    transferWiring,
    /OrganizationCreation|AuthUser|SUPABASE_PUBLISHABLE_KEY|SessionContext/i,
  );
  assert.match(transferModule, /IdentityVerifier/);
  assert.doesNotMatch(
    transferModule,
    /OrganizationCreation|AuthUser|SessionContext|app_private/i,
  );

  const transferRoute = productionServer.slice(
    productionServer.indexOf("const ownerTransferMatch"),
    productionServer.indexOf("const requestUrl"),
  );
  assert.doesNotMatch(
    `${transferModule}\n${transferRoute}`,
    /console\.|process\.(?:stdout|stderr)|\blogger\b/i,
  );
});
