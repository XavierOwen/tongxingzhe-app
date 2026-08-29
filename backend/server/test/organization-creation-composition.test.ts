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

test("production composition uses the dedicated organization creation chain", () => {
  assert.match(
    productionMain,
    /createOrganizationCreationIdentityVerifier\(/,
  );
  assert.match(productionMain, /createSupabaseAuthUserLookup\(/);
  assert.match(productionMain, /SUPABASE_PUBLISHABLE_KEY/);
  assert.match(productionMain, /new PostgresOrganizationCreationStore\(/);
  assert.match(productionMain, /organizationCreationIdentityVerifier,/);
  assert.match(productionMain, /organizationCreationStore,/);
  assert.doesNotMatch(productionMain, /app_private/);
  assert.doesNotMatch(productionMain, /service[_-]?role/i);
  assert.doesNotMatch(productionMain, /JWT_SECRET|AUTH_SECRET/);
});

test("server composition exposes only the fixed organization creation route", () => {
  assert.match(productionServer, /handleOrganizationCreation/);
  assert.match(
    productionServer,
    /organizationCreationIdentityVerifier\?:/,
  );
  assert.match(productionServer, /organizationCreationStore\?:/);
  assert.match(productionServer, /request\.method === "POST"/);
  assert.match(productionServer, /requestUrl\.pathname === "\/v1\/organizations"/);
  assert.doesNotMatch(productionServer, /app_private/);
});
