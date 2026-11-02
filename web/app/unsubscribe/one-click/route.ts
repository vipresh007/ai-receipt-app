import { backendUrl } from "@/lib/backend";

/** RFC 8058 one-click unsubscribe: mail apps (Gmail, Apple Mail) POST here
 * from their own Unsubscribe button. A plain GET just shows the confirm page. */
export async function POST(req: Request) {
  const url = new URL(req.url);
  const e = url.searchParams.get("e") ?? "";
  const s = url.searchParams.get("s") ?? "";
  const t = url.searchParams.get("t") ?? "";
  const res = await fetch(backendUrl("v1/public/unsubscribe"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ e, s, t }),
    cache: "no-store",
  });
  return new Response(null, { status: res.ok ? 200 : 400 });
}

export async function GET(req: Request) {
  const url = new URL(req.url);
  url.pathname = "/unsubscribe";
  return Response.redirect(url, 303);
}
