import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = readFileSync(
  fileURLToPath(new URL("../../src/main.ts", import.meta.url)),
  "utf8",
);

test("production composition injects the 6AQ current-city adapter", () => {
  assert.match(
    productionMain,
    /PostgresManagementCurrentCityReportSnapshotStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementCurrentCityReportSnapshotStore\(/,
  );
  assert.match(productionMain, /managementCurrentCityReportSnapshotStore,/);
  assert.doesNotMatch(productionMain, /app_private/);
});
