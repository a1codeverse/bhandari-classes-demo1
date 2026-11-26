function decode64url(s) {
  const a = s.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(a + "=".repeat((4 - a.length % 4) % 4));
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}
async function verifyToken(token, secret) {
  const parts = token.split(".");
  if (parts.length !== 2) return null;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), {name:"HMAC",hash:"SHA-256"}, false, ["verify"]);
  const valid = await crypto.subtle.verify("HMAC", key, decode64url(parts[1]), new TextEncoder().encode(parts[0]));
  if (!valid) return null;
  try {
    const claims = JSON.parse(new TextDecoder().decode(decode64url(parts[0])));
    if (!claims.key || !claims.sub || !claims.lessonId || !Number.isInteger(claims.exp)) return null;
    if (claims.exp <= Math.floor(Date.now()/1000) || !claims.key.startsWith("videos/")) return null;
    return claims;
  } catch { return null; }
}
function parseRange(value, size) {
  if (!value) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(value.trim());
  if (!match) return {invalid:true};
  let start = match[1] ? Number(match[1]) : null;
  let end = match[2] ? Number(match[2]) : null;
  if (start === null && end !== null) { start = Math.max(0, size-end); end = size-1; }
  else { start = start ?? 0; end = end === null ? size-1 : Math.min(end, size-1); }
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start > end || start >= size) return {invalid:true};
  return {offset:start, length:end-start+1, start, end};
}
function corsHeaders(request, env) {
  const origin = request.headers.get("Origin");
  const headers = {"Vary":"Origin","Access-Control-Allow-Methods":"GET, HEAD, OPTIONS","Access-Control-Allow-Headers":"Range, Content-Type","Access-Control-Expose-Headers":"Accept-Ranges, Content-Length, Content-Range, ETag"};
  if (origin && origin === env.CORS_ORIGIN) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}
export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);
    if (request.method === "OPTIONS") return new Response(null,{status:204,headers:cors});
    if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed",{status:405,headers:cors});
    const token = new URL(request.url).searchParams.get("token");
    if (!token || !env.MEDIA_TOKEN_SECRET) return new Response("Unauthorized",{status:401,headers:cors});
    const claims = await verifyToken(token, env.MEDIA_TOKEN_SECRET);
    if (!claims) return new Response("Expired or invalid media token",{status:403,headers:cors});
    const head = await env.VIDEOS.head(claims.key);
    if (!head) return new Response("Not found",{status:404,headers:cors});
    const range = parseRange(request.headers.get("Range"),head.size);
    if (range && range.invalid) return new Response(null,{status:416,headers:{...cors,"Content-Range":"bytes */"+head.size}});
    const object = await env.VIDEOS.get(claims.key, range ? {range:{offset:range.offset,length:range.length}} : undefined);
    if (!object) return new Response("Not found",{status:404,headers:cors});
    const headers = {...cors,"Accept-Ranges":"bytes","Content-Type":object.httpMetadata?.contentType || "video/mp4","Cache-Control":"private, no-store, max-age=0","Content-Disposition":"inline","ETag":object.httpEtag || head.etag};
    if (range) { headers["Content-Length"]=String(range.length); headers["Content-Range"]="bytes "+range.start+"-"+range.end+"/"+head.size; }
    else headers["Content-Length"]=String(head.size);
    return new Response(request.method==="HEAD" ? null : object.body,{status:range?206:200,headers});
  }
};