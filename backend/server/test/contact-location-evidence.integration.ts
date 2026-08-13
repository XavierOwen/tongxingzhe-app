import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { Pool, type PoolClient } from "pg";

import { handleSyncCommand } from "../src/sync-command.js";
import { PostgresSessionContextStore } from "../src/session-context.js";
import { PostgresSyncCommandStore } from "../src/sync-store.js";

const treeVersion = "regions-slice6v-v1";
const cityRegionId = "region-slice6v-chicago";
const venueRegionId = "region-slice6v-university";
const publishedFingerprint =
  "b51b4f8d4a9a6b0c0dc12eff0c41459780ac34d8ee9b9f75919ea69b7fa89127";
const latitude = 41.7897;
const longitude = -87.5997;
const identity = {
  issuer: "https://synthetic-slice6v.supabase.co/auth/v1",
  subject: "synthetic-slice6v-owner",
};
const fixture = loadLocationSourceFixture();

const databaseUrl = process.env.DATABASE_URL;
if (databaseUrl === undefined || databaseUrl.trim().length === 0) {
  throw new Error("DATABASE_URL is required for location evidence integration");
}

const pool = new Pool({ connectionString: databaseUrl });
const client = await pool.connect();

try {
  await client.query("BEGIN");
  await installSyntheticRegionTree(client);
  await client.query("SET LOCAL ROLE tongxingzhe_runtime");

  const query = async (text: string, values: readonly unknown[]) =>
    client.query(text, [...values]);
  const contextStore = new PostgresSessionContextStore(async (text, values) =>
    query(text, values)
  );
  const commandStore = new PostgresSyncCommandStore(query);
  const dependencies = {
    identityVerifier: { verify: async () => identity },
    contextStore,
    commandStore,
  };
  const context = await contextStore.loadOrCreate(identity);
  const scope = {
    workspaceId: context.current.workspace.id,
    projectId: context.current.project.id,
    questionnaireVersionId: context.current.questionnaireVersion.id,
  };

  const acceptedFixture = fixture.filter(
    (fixtureCase) => fixtureCase.expectedFailureCode === "",
  );
  const cases = acceptedFixture.map((fixtureCase) => ({
    contactId: fixtureContactId(fixtureCase.caseName),
    channel: fixtureCase.channel,
    location: locationToWire(fixtureCase.location),
    ...(fixtureCase.locationSource === null
      ? {}
      : { locationSource: sourceToWire(fixtureCase.locationSource) }),
  }));
  const coordinateFixture = fixtureByName(
    acceptedFixture,
    "resolved_with_coordinates",
  );
  const coordinateCase = cases.find(
    (fixtureCase) =>
      fixtureCase.contactId === fixtureContactId(coordinateFixture.caseName),
  );
  assert.ok(coordinateCase);
  const coordinateContact = coordinateCase.contactId;

  for (const fixtureCase of cases) {
    const response = await handleSyncCommand(
      "Bearer synthetic-token",
      submitCommand({ ...scope, ...fixtureCase }),
      dependencies,
    );
    assert.deepEqual(response.body, {
      result: "accepted",
      server_cursor: assertCursor(response.body.server_cursor),
    }, fixtureCase.contactId);
  }

  const duplicate = await handleSyncCommand(
    "Bearer synthetic-token",
    submitCommand({ ...scope, ...coordinateCase }),
    dependencies,
  );
  assert.equal(duplicate.body.result, "duplicate");

  const revisedSource = capturedSource(41.7901, -87.5991, 9.1);
  assert.equal(
    (await handleSyncCommand(
      "Bearer synthetic-token",
      revisionCommand({
        ...scope,
        contactId: coordinateContact,
        commandId: "slice6v-coordinate-revise",
        baseRevision: 1,
        reason: "Move the captured point",
        location: resolvedLocation("University of Chicago East"),
        locationSource: revisedSource,
        interestLevel: 2,
      }),
      dependencies,
    )).status,
    200,
  );

  assert.equal(
    (await handleSyncCommand(
      "Bearer synthetic-token",
      revisionCommand({
        ...scope,
        contactId: coordinateContact,
        commandId: "slice6v-coordinate-auto-merge",
        baseRevision: 1,
        reason: "Update interest from a stale device",
        location: resolvedLocation("University of Chicago"),
        locationSource: capturedSource(latitude, longitude, 8.5),
        interestLevel: 4,
      }),
      dependencies,
    )).status,
    200,
  );

  const proposedSource = capturedSource(41.7902, -87.5992, 9.2);
  const conflict = await handleSyncCommand(
    "Bearer synthetic-token",
    revisionCommand({
      ...scope,
      contactId: coordinateContact,
      commandId: "slice6v-coordinate-conflict",
      baseRevision: 1,
      reason: "Competing captured point",
      location: resolvedLocation("University of Chicago South"),
      locationSource: proposedSource,
      interestLevel: 2,
    }),
    dependencies,
  );
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.result, "conflict");
  const conflictBody = requireRecord(conflict.body.conflict, "conflict body");
  assert.deepEqual(conflictBody.conflicting_fields, ["location"]);
  const currentSnapshot = requireRecord(
    conflictBody.current_snapshot,
    "current snapshot",
  );
  const proposedSnapshot = requireRecord(
    conflictBody.proposed_snapshot,
    "proposed snapshot",
  );
  assert.deepEqual(currentSnapshot.locationSource, camelSource(revisedSource));
  assert.deepEqual(proposedSnapshot.locationSource, camelSource(proposedSource));

  const resolution = await handleSyncCommand(
    "Bearer synthetic-token",
    resolutionCommand({
      ...scope,
      contactId: coordinateContact,
      conflictId: requireString(conflictBody.conflict_id, "conflict ID"),
      location: resolvedLocation("University of Chicago South"),
      locationSource: proposedSource,
    }),
    dependencies,
  );
  assert.equal(resolution.status, 200);

  const voidResponse = await handleSyncCommand(
    "Bearer synthetic-token",
    voidCommand({ ...scope, contactId: coordinateContact }),
    dependencies,
  );
  assert.equal(voidResponse.status, 200);

  await client.query("SAVEPOINT malformed_source");
  const malformedFixture = fixtureByName(fixture, "malformed_fingerprint");
  const malformedSource = malformedFixture.locationSource;
  assert.ok(malformedSource);
  const malformed = await handleSyncCommand(
    "Bearer synthetic-token",
    submitCommand({
      ...scope,
      contactId: fixtureContactId(malformedFixture.caseName),
      channel: malformedFixture.channel,
      location: locationToWire(malformedFixture.location),
      locationSource: sourceToWire(malformedSource),
    }),
    dependencies,
  );
  assert.equal(malformed.status, 422);
  assert.deepEqual(malformed.body, {
    result: "rejected",
    error: { code: malformedFixture.expectedFailureCode },
  });
  const malformedText = JSON.stringify(malformed.body);
  assert.equal(malformedText.includes(String(latitude)), false);
  assert.equal(malformedText.includes(String(longitude)), false);
  await client.query("ROLLBACK TO SAVEPOINT malformed_source");

  await client.query("RESET ROLE");
  await verifyStoredEvidence(
    client,
    coordinateContact,
    Object.fromEntries(
      acceptedFixture.map((fixtureCase) => [
        fixtureContactId(fixtureCase.caseName),
        fixtureCase.expectedEvidenceKind,
      ]),
    ),
  );
  await verifyPrivacyBoundaries(client, scope.projectId);
  process.stdout.write(
    "Backend to PostgreSQL location evidence integration: passed\n",
  );
} finally {
  try {
    await client.query("ROLLBACK");
  } finally {
    client.release();
    await pool.end();
  }
}

async function installSyntheticRegionTree(client: PoolClient): Promise<void> {
  await client.query(`
    INSERT INTO app_data.canonical_region_tree_releases (
      tree_version, lifecycle_state, is_current
    ) VALUES ('${treeVersion}', 'draft', false);
    INSERT INTO app_data.canonical_region_versions (
      region_id, tree_version, parent_region_id, canonical_name, kind
    ) VALUES
      ('region-slice6v-country', '${treeVersion}', NULL,
       'Synthetic Country', 'country'),
      ('${cityRegionId}', '${treeVersion}', 'region-slice6v-country',
       'Chicago', 'city'),
      ('${venueRegionId}', '${treeVersion}', '${cityRegionId}',
       'University of Chicago', 'venue');
    INSERT INTO app_data.canonical_region_boundaries (
      boundary_id, region_id, tree_version, boundary
    ) VALUES (
      'boundary-slice6v-university', '${venueRegionId}', '${treeVersion}',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    );
  `);
  const result = await client.query<{ content_fingerprint: string }>(
    `SELECT app_private.publish_canonical_region_tree_v1($1, true)
       ->> 'content_fingerprint' AS content_fingerprint`,
    [treeVersion],
  );
  assert.equal(result.rows[0]?.content_fingerprint, publishedFingerprint);
}

async function verifyStoredEvidence(
  client: PoolClient,
  coordinateContact: string,
  expectedFirstRevisionKinds: Readonly<Record<string, string>>,
): Promise<void> {
  const evidence = await client.query<{
    contact_id: string;
    revision_number: number;
    evidence_kind: string;
    latitude: number | null;
    longitude: number | null;
    region_tree_content_fingerprint: string | null;
  }>(`
    SELECT contact_id, revision_number, evidence_kind, latitude, longitude,
           region_tree_content_fingerprint
    FROM app_data.contact_location_provenance
    WHERE contact_id LIKE 'slice6v-%-contact'
    ORDER BY contact_id, revision_number
  `);
  const firstRevisionKinds = Object.fromEntries(
    evidence.rows
      .filter((row) => row.revision_number === 1)
      .map((row) => [row.contact_id, row.evidence_kind]),
  );
  assert.deepEqual(firstRevisionKinds, expectedFirstRevisionKinds);
  const coordinateRows = evidence.rows.filter(
    (row) => row.contact_id === coordinateContact,
  );
  assert.equal(coordinateRows.length, 5);
  assert.deepEqual(
    coordinateRows.map((row) => row.revision_number),
    [1, 2, 3, 4, 5],
  );
  assert.equal(
    coordinateRows.every(
      (row) =>
        row.evidence_kind === "resolved_from_coordinates" &&
        row.region_tree_content_fingerprint === publishedFingerprint,
    ),
    true,
  );
  assert.equal(coordinateRows[0]?.latitude, latitude);
  assert.equal(coordinateRows[0]?.longitude, longitude);
  assert.equal(coordinateRows[2]?.latitude, 41.7901);
  assert.equal(coordinateRows[3]?.latitude, 41.7902);
  assert.equal(coordinateRows[4]?.latitude, 41.7902);
}

async function verifyPrivacyBoundaries(
  client: PoolClient,
  projectId: string,
): Promise<void> {
  const warehouse = await client.query<{ analytics_payload: unknown }>(`
    SELECT analytics_payload
    FROM app_data.warehouse_outbox
    WHERE contact_id LIKE 'slice6v-%-contact'
  `);
  assert.equal(warehouse.rows.length, 8);
  for (const row of warehouse.rows) {
    const text = JSON.stringify(row.analytics_payload);
    assert.equal(/location|latitude|longitude/i.test(text), false);
    for (const coordinate of [
      "41.7897", "-87.5997", "41.7901", "-87.5991", "41.7902",
      "-87.5992",
    ]) {
      assert.equal(text.includes(coordinate), false);
    }
  }
  const privilege = await client.query<{ can_read: boolean }>(`
    SELECT has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.contact_location_provenance',
      'SELECT'
    ) AS can_read
  `);
  assert.equal(privilege.rows[0]?.can_read, false);

  await client.query(
     `UPDATE app_data.workspaces
     SET workspace_kind = 'organization',
         personal_owner_app_user_id = NULL
     WHERE workspace_id = (
       SELECT workspace_id FROM app_data.projects WHERE project_id = $1
     )`,
    [projectId],
  );
  const report = await client.query<{ protected_report: unknown }>(
    `SELECT app_private.execute_management_contact_session_report_v1(
       $1::uuid,
       'contact_sessions_by_channel_two_periods',
       1,
       'America/Chicago',
       '2030-02-12T12:00:00Z'
     ) AS protected_report`,
    [projectId],
  );
  assertNoExactLocation(
    JSON.stringify(report.rows[0]?.protected_report),
    "anonymous management report",
  );
}

function assertNoExactLocation(value: string, boundary: string): void {
  assert.equal(/location|latitude|longitude/i.test(value), false, boundary);
  for (const coordinate of [
    "41.7897", "-87.5997", "41.7901", "-87.5991", "41.7902",
    "-87.5992",
  ]) {
    assert.equal(value.includes(coordinate), false, boundary);
  }
}

interface LocationSourceFixtureCase {
  readonly caseName: string;
  readonly channel: string;
  readonly location: Readonly<Record<string, unknown>>;
  readonly locationSource: Readonly<Record<string, unknown>> | null;
  readonly expectedEvidenceKind: string;
  readonly expectedFailureCode: string;
}

function loadLocationSourceFixture(): readonly LocationSourceFixtureCase[] {
  const fixturePath = fileURLToPath(
    new URL(
      "../../../database/fixtures/shared/contact_location_source_v1.csv",
      import.meta.url,
    ),
  );
  const [header, ...rows] = readFileSync(fixturePath, "utf8")
    .trim()
    .split("\n");
  assert.equal(
    header,
    "case_name,channel,location_json,location_source_json," +
      "expected_evidence_kind,expected_failure_code",
  );
  return rows.map((row) => {
    const fields = csvFields(row);
    assert.equal(fields.length, 6);
    const [
      caseName,
      channel,
      locationJson,
      locationSourceJson,
      expectedEvidenceKind,
      expectedFailureCode,
    ] = fields as [string, string, string, string, string, string];
    assert.ok(caseName);
    assert.ok(channel);
    assert.ok(locationJson);
    assert.ok(expectedEvidenceKind);
    const location = requireRecord(
      JSON.parse(locationJson) as unknown,
      `${caseName} location`,
    );
    const locationSource = locationSourceJson === ""
      ? null
      : requireRecord(
        JSON.parse(locationSourceJson) as unknown,
        `${caseName} source`,
      );
    return {
      caseName,
      channel,
      location,
      locationSource,
      expectedEvidenceKind,
      expectedFailureCode,
    };
  });
}

function fixtureByName(
  values: readonly LocationSourceFixtureCase[],
  caseName: string,
): LocationSourceFixtureCase {
  const value = values.find((fixtureCase) => fixtureCase.caseName === caseName);
  assert.ok(value, `missing fixture case ${caseName}`);
  return value;
}

function fixtureContactId(caseName: string): string {
  const ids: Readonly<Record<string, string>> = {
    resolved_with_coordinates: "slice6v-coordinate-contact",
    resolved_region_only: "slice6v-region-only-contact",
    pending_resolution: "slice6v-pending-contact",
    not_applicable: "slice6v-na-contact",
    malformed_fingerprint: "slice6v-malformed-source-contact",
  };
  return requireString(ids[caseName], `${caseName} contact ID`);
}

function locationToWire(
  value: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
  if (value.kind === "not_applicable") {
    return { kind: "not_applicable" };
  }
  if (value.kind === "pending_resolution") {
    return {
      kind: "pending_resolution",
      latitude: value.latitude,
      longitude: value.longitude,
      accuracy_meters: value.accuracyMeters,
    };
  }
  if (value.kind === "resolved") {
    return {
      kind: "resolved",
      place_name: value.placeName,
      smallest_region_id: value.smallestRegionId,
      region_tree_version: value.regionTreeVersion,
    };
  }
  throw new Error("fixture location kind is unsupported");
}

function sourceToWire(
  value: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
  return {
    kind: value.kind,
    latitude: value.latitude,
    longitude: value.longitude,
    accuracy_meters: value.accuracyMeters,
    resolver_contract_version: value.resolverContractVersion,
    region_tree_content_fingerprint: value.regionTreeContentFingerprint,
  };
}

function csvFields(line: string): string[] {
  const fields: string[] = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        field += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      fields.push(field);
      field = "";
    } else {
      field += character;
    }
  }
  if (quoted) throw new Error("unterminated CSV field");
  fields.push(field);
  return fields;
}

function submitCommand(input: {
  readonly workspaceId: string;
  readonly projectId: string;
  readonly questionnaireVersionId: string;
  readonly contactId: string;
  readonly channel: string;
  readonly location: Readonly<Record<string, unknown>>;
  readonly locationSource?: Readonly<Record<string, unknown>>;
}): Readonly<Record<string, unknown>> {
  return {
    protocol_version: 1,
    command_id: `${input.contactId}-submit`,
    device_id: "slice6v-device-a",
    aggregate_id: input.contactId,
    base_revision: 0,
    type: "contact.submit.v1",
    typed_payload: {
      contact_id: input.contactId,
      workspace_id: input.workspaceId,
      project_id: input.projectId,
      questionnaire_version_id: input.questionnaireVersionId,
      occurred_at_utc: "2030-02-02T12:00:00.000Z",
      occurred_time_zone: "America/Chicago",
      channel: input.channel,
      channel_detail: null,
      location: input.location,
      ...(input.locationSource === undefined
        ? {}
        : { location_source: input.locationSource }),
      reach_count: 1,
      interest_level: 2,
      answers: [],
    },
  };
}

function revisionCommand(input: {
  readonly workspaceId: string;
  readonly projectId: string;
  readonly contactId: string;
  readonly commandId: string;
  readonly baseRevision: number;
  readonly reason: string;
  readonly location: Readonly<Record<string, unknown>>;
  readonly locationSource?: Readonly<Record<string, unknown>>;
  readonly interestLevel: number;
}): Readonly<Record<string, unknown>> {
  return {
    protocol_version: 1,
    command_id: input.commandId,
    device_id: "slice6v-device-b",
    aggregate_id: input.contactId,
    base_revision: input.baseRevision,
    type: "contact.revise.v1",
    typed_payload: {
      contact_id: input.contactId,
      workspace_id: input.workspaceId,
      project_id: input.projectId,
      reason: input.reason,
      occurred_at_utc: "2030-02-02T12:00:00.000Z",
      occurred_time_zone: "America/Chicago",
      channel: "face_to_face",
      channel_detail: null,
      location: input.location,
      ...(input.locationSource === undefined
        ? {}
        : { location_source: input.locationSource }),
      reach_count: 1,
      interest_level: input.interestLevel,
      answers: [],
    },
  };
}

function resolutionCommand(input: {
  readonly workspaceId: string;
  readonly projectId: string;
  readonly contactId: string;
  readonly conflictId: string;
  readonly location: Readonly<Record<string, unknown>>;
  readonly locationSource: Readonly<Record<string, unknown>>;
}): Readonly<Record<string, unknown>> {
  const command = revisionCommand({
    ...input,
    commandId: "slice6v-coordinate-resolution",
    baseRevision: 3,
    reason: "Choose the competing captured point",
    interestLevel: 2,
  });
  return {
    ...command,
    type: "contact.resolve.v1",
    typed_payload: {
      ...requireRecord(command.typed_payload, "resolution payload"),
      conflict_id: input.conflictId,
    },
  };
}

function voidCommand(input: {
  readonly workspaceId: string;
  readonly projectId: string;
  readonly contactId: string;
}): Readonly<Record<string, unknown>> {
  return {
    protocol_version: 1,
    command_id: "slice6v-coordinate-void",
    device_id: "slice6v-device-b",
    aggregate_id: input.contactId,
    base_revision: 4,
    type: "contact.void.v1",
    typed_payload: {
      contact_id: input.contactId,
      workspace_id: input.workspaceId,
      project_id: input.projectId,
      reason: "Void synthetic contact",
    },
  };
}

function resolvedLocation(placeName: string): Readonly<Record<string, unknown>> {
  return {
    kind: "resolved",
    place_name: placeName,
    smallest_region_id: venueRegionId,
    region_tree_version: treeVersion,
  };
}

function capturedSource(
  sourceLatitude: number,
  sourceLongitude: number,
  accuracyMeters: number,
): Readonly<Record<string, unknown>> {
  return {
    kind: "captured_coordinates",
    latitude: sourceLatitude,
    longitude: sourceLongitude,
    accuracy_meters: accuracyMeters,
    resolver_contract_version: "canonical-region-resolution:v1",
    region_tree_content_fingerprint: publishedFingerprint,
  };
}

function camelSource(
  value: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
  return {
    kind: value.kind,
    latitude: value.latitude,
    longitude: value.longitude,
    accuracyMeters: value.accuracy_meters,
    resolverContractVersion: value.resolver_contract_version,
    regionTreeContentFingerprint: value.region_tree_content_fingerprint,
  };
}

function assertCursor(value: unknown): string {
  return requireString(value, "server cursor");
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} is missing`);
  }
  return value;
}

function requireRecord(
  value: unknown,
  name: string,
): Readonly<Record<string, unknown>> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${name} is missing`);
  }
  return value as Readonly<Record<string, unknown>>;
}
