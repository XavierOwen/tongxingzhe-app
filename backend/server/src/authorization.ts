/**
 * 解析单个 HTTP Authorization Bearer 值。
 *
 * 所有受保护端点共用这一份严格合同，避免有的路由接受多余空格或多个 token，
 * 另一些路由却拒绝同一请求。
 */
export function bearerToken(
  authorization: string | undefined,
): string | null {
  if (authorization === undefined) {
    return null;
  }
  return /^Bearer ([^\s,]+)$/i.exec(authorization.trim())?.[1] ?? null;
}
