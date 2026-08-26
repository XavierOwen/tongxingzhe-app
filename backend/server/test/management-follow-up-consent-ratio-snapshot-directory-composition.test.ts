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

test("production composition injects the independent consent-ratio directory adapter", () => {
  assert.match(
    productionMain,
    /PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore\(/,
  );
  assert.match(
    productionMain,
    /managementFollowUpConsentRatioSnapshotDirectoryStore,/,
  );
  assert.doesNotMatch(productionMain, /app_private/);
});

test("server composition keeps consent-ratio collection and detail routes separate", () => {
  assert.match(
    productionServer,
    /listManagementFollowUpConsentRatioSnapshotDirectory/,
  );
  assert.match(
    productionServer,
    /managementFollowUpConsentRatioSnapshotDirectoryStore\?:/,
  );
  assert.match(
    productionServer,
    /management-follow-up-consent-ratio-report-snapshots\$/,
  );
  assert.match(
    productionServer,
    /management-follow-up-consent-ratio-report-snapshots\\\/\(\[\^\/\]\+\)\$/,
  );
  assert.doesNotMatch(productionServer, /app_private/);
});
