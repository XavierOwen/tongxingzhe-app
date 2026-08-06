/** Slice 1 时已发布的 protocol v1 command，用于防止服务端破坏旧客户端。 */
export const syncContractV1Fixture: Readonly<Record<string, unknown>> = {
  protocol_version: 1,
  command_id: "legacy-command-1",
  device_id: "legacy-device-1",
  aggregate_id: "legacy-contact-1",
  base_revision: 0,
  type: "contact.submit.v1",
  typed_payload: {
    contact_id: "legacy-contact-1",
    workspace_id: "22222222-2222-4222-8222-222222222222",
    project_id: "33333333-3333-4333-8333-333333333333",
    questionnaire_version_id: "44444444-4444-4444-8444-444444444444",
    occurred_at_utc: "2030-01-08T18:00:00.000Z",
    occurred_time_zone: "America/Chicago",
    channel: "video_call",
    channel_detail: null,
    location: { kind: "not_applicable" },
    reach_count: 2,
    interest_level: 3,
    answers: [],
  },
};
