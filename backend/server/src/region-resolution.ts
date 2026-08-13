import { bearerToken } from "./authorization.js";
import {
  IdentityVerificationError,
  type IdentityVerifier,
} from "./identity.js";

export interface CanonicalRegionNode {
  readonly regionId: string;
  readonly parentRegionId: string | null;
  readonly canonicalName: string;
  readonly kind: string;
  readonly attributes: readonly string[];
}

export interface ResolvedCanonicalRegion {
  readonly regionId: string;
  readonly treeVersion: string;
  readonly canonicalName: string;
  readonly contentFingerprint: string;
  readonly resolverContractVersion: "canonical-region-resolution:v1";
  readonly regionPath: readonly CanonicalRegionNode[];
}

/** 只暴露坐标解析；实现隐藏边界表、当前发布版本和 SQL。 */
export interface RegionResolutionStore {
  resolve(
    latitude: number,
    longitude: number,
  ): Promise<ResolvedCanonicalRegion | null>;
}

export interface RegionResolutionDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly regionResolutionStore: RegionResolutionStore;
}

export interface RegionResolutionHttpResult {
  readonly status: number;
  readonly body: Readonly<Record<string, unknown>>;
}

/**
 * 验证 bearer 身份和坐标后解析当前规范区域。
 * 命中返回可安装父链；未命中返回 pending；身份、输入和服务失败使用稳定状态码。
 * 此函数不接收或回显业务用户 ID，也不暴露边界数据。
 */
export async function resolveContactRegion(
  authorization: string | undefined,
  body: unknown,
  dependencies: RegionResolutionDependencies,
): Promise<RegionResolutionHttpResult> {
  const accessToken = bearerToken(authorization);
  if (accessToken === null) {
    return failure(401, "unauthenticated");
  }
  const coordinates = parseCoordinates(body);
  if (coordinates === null) {
    return failure(400, "invalid_coordinates");
  }

  try {
    await dependencies.identityVerifier.verify(accessToken);
    const resolved = await dependencies.regionResolutionStore.resolve(
      coordinates.latitude,
      coordinates.longitude,
    );
    if (resolved === null) {
      return { status: 202, body: { result: "pending" } };
    }
    return {
      status: 200,
      body: {
        result: "resolved",
        location: {
          kind: "resolved",
          place_name: resolved.canonicalName,
          smallest_region_id: resolved.regionId,
          region_tree_version: resolved.treeVersion,
        },
        region_tree: {
          version: resolved.treeVersion,
          content_fingerprint: resolved.contentFingerprint,
          resolver_contract_version: resolved.resolverContractVersion,
          nodes: resolved.regionPath.map((node) => ({
            region_id: node.regionId,
            parent_region_id: node.parentRegionId,
            canonical_name: node.canonicalName,
            kind: node.kind,
            attributes: node.attributes,
          })),
        },
      },
    };
  } catch (error) {
    if (error instanceof IdentityVerificationError) {
      return failure(401, "unauthenticated");
    }
    return failure(503, "region_resolution_unavailable");
  }
}

export type RegionResolutionQuery = (
  text: string,
  values: readonly unknown[],
) => Promise<{ readonly rows: readonly unknown[] }>;

interface RegionResolutionRow {
  readonly region_id: unknown;
  readonly tree_version: unknown;
  readonly canonical_name: unknown;
  readonly content_fingerprint: unknown;
  readonly resolver_contract_version: unknown;
  readonly region_path: unknown;
}

export class PostgresRegionResolutionStore implements RegionResolutionStore {
  constructor(private readonly query: RegionResolutionQuery) {}

  async resolve(
    latitude: number,
    longitude: number,
  ): Promise<ResolvedCanonicalRegion | null> {
    const result = await this.query(
      `SELECT region_id, tree_version, canonical_name,
              content_fingerprint, resolver_contract_version, region_path
       FROM app_data.resolve_canonical_region_with_provenance(
         $1::double precision,
         $2::double precision
       )`,
      [latitude, longitude],
    );
    if (result.rows.length === 0) {
      return null;
    }
    if (result.rows.length !== 1) {
      throw new Error("Region resolver returned more than one row");
    }
    return parseResolutionRow(result.rows[0]);
  }
}

function parseCoordinates(
  body: unknown,
): { readonly latitude: number; readonly longitude: number } | null {
  if (typeof body !== "object" || body === null) {
    return null;
  }
  const value = body as { latitude?: unknown; longitude?: unknown };
  if (
    typeof value.latitude !== "number" ||
    !Number.isFinite(value.latitude) ||
    value.latitude < -90 ||
    value.latitude > 90 ||
    typeof value.longitude !== "number" ||
    !Number.isFinite(value.longitude) ||
    value.longitude < -180 ||
    value.longitude > 180
  ) {
    return null;
  }
  return { latitude: value.latitude, longitude: value.longitude };
}

function parseResolutionRow(value: unknown): ResolvedCanonicalRegion {
  if (typeof value !== "object" || value === null) {
    throw new Error("Region resolver returned a non-object row");
  }
  const row = value as RegionResolutionRow;
  const path = row.region_path;
  if (!Array.isArray(path) || path.length === 0) {
    throw new Error("Region resolver returned an empty path");
  }
  const regionPath = path.map(parseRegionNode);
  const regionId = requiredString(row.region_id, "region_id");
  const treeVersion = requiredString(row.tree_version, "tree_version");
  const canonicalName = requiredString(row.canonical_name, "canonical_name");
  const contentFingerprint = requiredFingerprint(row.content_fingerprint);
  const resolverContractVersion = requiredResolverContract(
    row.resolver_contract_version,
  );
  if (regionPath.at(-1)?.regionId !== regionId) {
    throw new Error("Region resolver path does not end at the matched node");
  }
  return {
    regionId,
    treeVersion,
    canonicalName,
    contentFingerprint,
    resolverContractVersion,
    regionPath,
  };
}

function parseRegionNode(value: unknown): CanonicalRegionNode {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Region resolver returned an invalid path node");
  }
  const node = value as Record<string, unknown>;
  const parent = node.parentRegionId;
  const attributes = node.attributes;
  if (
    (parent !== null && typeof parent !== "string") ||
    !Array.isArray(attributes) ||
    attributes.some((attribute) => typeof attribute !== "string")
  ) {
    throw new Error("Region resolver returned an invalid path node");
  }
  return {
    regionId: requiredString(node.regionId, "regionId"),
    parentRegionId: parent,
    canonicalName: requiredString(node.canonicalName, "canonicalName"),
    kind: requiredString(node.kind, "kind"),
    attributes: attributes as readonly string[],
  };
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Region resolver returned invalid ${name}`);
  }
  return value;
}

function requiredFingerprint(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/.test(value)) {
    throw new Error("Region resolver returned an invalid content fingerprint");
  }
  return value;
}

function requiredResolverContract(
  value: unknown,
): "canonical-region-resolution:v1" {
  if (value !== "canonical-region-resolution:v1") {
    throw new Error("Region resolver returned an unsupported resolver contract");
  }
  return value;
}

function failure(status: number, code: string): RegionResolutionHttpResult {
  return { status, body: { error: { code } } };
}
