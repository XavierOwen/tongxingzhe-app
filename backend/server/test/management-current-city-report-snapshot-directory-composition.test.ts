import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import {fileURLToPath} from "node:url";

const productionMain = readFileSync(
  fileURLToPath(new URL("../../src/main.ts", import.meta.url)),
  "utf8",
);

test("production composition injects the 6AS current-city directory adapter", () => {
  assert.match(
    productionMain,
    /PostgresManagementCurrentCityReportSnapshotDirectoryStore/,
  );
  assert.match(
    productionMain,
    /new PostgresManagementCurrentCityReportSnapshotDirectoryStore\(/,
  );
  assert.match(
    productionMain,
    /managementCurrentCityReportSnapshotDirectoryStore,/,
  );
  assert.doesNotMatch(productionMain, /app_private/);
});
