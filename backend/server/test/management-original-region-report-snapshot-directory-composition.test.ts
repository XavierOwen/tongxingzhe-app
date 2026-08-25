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

test("production composition injects the independent original-region directory adapter", () => {
  assert.match(
    productionMain,
    /PostgresManagementOriginalRegionReportSnapshotDirectoryStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementOriginalRegionReportSnapshotDirectoryStore\(/,
  );
  assert.match(
    productionMain,
    /managementOriginalRegionReportSnapshotDirectoryStore,/,
  );
  assert.doesNotMatch(productionMain, /app_private/);
});

test("server composition keeps original-region collection and detail routes separate", () => {
  assert.match(
    productionServer,
    /listManagementOriginalRegionReportSnapshotDirectory/,
  );
  assert.match(
    productionServer,
    /managementOriginalRegionReportSnapshotDirectoryStore\?:/,
  );
  assert.match(
    productionServer,
    /management-original-region-report-snapshots\$/,
  );
  assert.match(
    productionServer,
    /management-original-region-report-snapshots\\\/\(\[\^\/\]\+\)\$/,
  );
  assert.doesNotMatch(productionServer, /app_private/);
});
