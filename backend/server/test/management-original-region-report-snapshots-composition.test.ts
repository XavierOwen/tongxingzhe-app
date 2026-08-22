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

test("production composition injects the original-region snapshot adapter and route", () => {
  assert.match(
    productionMain,
    /PostgresManagementOriginalRegionReportSnapshotStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementOriginalRegionReportSnapshotStore\(/,
  );
  assert.match(
    productionMain,
    /managementOriginalRegionReportSnapshotStore,/,
  );
  assert.match(productionServer, /readManagementOriginalRegionReportSnapshot/);
  assert.match(
    productionServer,
    /managementOriginalRegionReportSnapshotStore/,
  );
  assert.match(productionServer, /management-original-region-report-snapshots/);
  assert.doesNotMatch(productionMain, /app_private/);
  assert.doesNotMatch(productionServer, /app_private/);
});
