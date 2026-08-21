import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = readFileSync(
  fileURLToPath(new URL("../../src/main.ts", import.meta.url)),
  "utf8",
);
const serverSource = readFileSync(
  fileURLToPath(new URL("../../src/server.ts", import.meta.url)),
  "utf8",
);

test("production composition injects the independent 6BA interest directory adapter", () => {
  assert.match(
    productionMain,
    /PostgresManagementInterestReportSnapshotDirectoryStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementInterestReportSnapshotDirectoryStore\(/,
  );
  assert.match(
    productionMain,
    /managementInterestReportSnapshotDirectoryStore,/,
  );
  assert.doesNotMatch(productionMain, /app_private/);
});

test("server composition keeps interest collection and 6AZ detail routes separate", () => {
  assert.match(
    serverSource,
    /listManagementInterestReportSnapshotDirectory/,
  );
  assert.match(
    serverSource,
    /managementInterestReportSnapshotDirectoryStore\?:/,
  );
  assert.match(
    serverSource,
    /management-interest-report-snapshots\$/,
  );
  assert.match(
    serverSource,
    /management-interest-report-snapshots\\\/\(\[\^\/\]\+\)\$/,
  );
  assert.doesNotMatch(serverSource, /app_private/);
});
