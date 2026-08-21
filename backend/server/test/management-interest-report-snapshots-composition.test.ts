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

test("production composition injects the 6AY interest snapshot adapter", () => {
  assert.match(productionMain, /PostgresManagementInterestReportSnapshotStore/);
  assert.match(
    productionMain,
    /new PostgresManagementInterestReportSnapshotStore\(/,
  );
  assert.match(productionMain, /managementInterestReportSnapshotStore,/);
  assert.match(productionServer, /readManagementInterestReportSnapshot/);
  assert.match(
    productionServer,
    /managementInterestReportSnapshotStore/,
  );
  assert.doesNotMatch(productionMain, /app_private/);
  assert.doesNotMatch(productionServer, /app_private/);
});
