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

test("production composition injects the consent-ratio snapshot adapter and route", () => {
  assert.match(
    productionMain,
    /PostgresManagementFollowUpConsentRatioReportSnapshotStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementFollowUpConsentRatioReportSnapshotStore\(/,
  );
  assert.match(
    productionMain,
    /managementFollowUpConsentRatioReportSnapshotStore,/,
  );
  assert.match(
    productionServer,
    /readManagementFollowUpConsentRatioReportSnapshot/,
  );
  assert.match(
    productionServer,
    /managementFollowUpConsentRatioReportSnapshotStore/,
  );
  assert.match(
    productionServer,
    /management-follow-up-consent-ratio-report-snapshots/,
  );
  assert.doesNotMatch(productionMain, /app_private/);
  assert.doesNotMatch(productionServer, /app_private/);
});
