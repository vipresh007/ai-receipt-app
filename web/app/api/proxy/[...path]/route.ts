import { type NextRequest, NextResponse } from "next/server";
import { auth0 } from "@/lib/auth0";
import { backendUrl } from "@/lib/backend";

type Ctx = { params: Promise<{ path: string[] }> };

async function forward(req: NextRequest, path: string[]): Promise<NextResponse> {
  let token: string | undefined;
  try {
    ({ token } = await auth0.getAccessToken());
  } catch {
    return NextResponse.json({ detail: "Not authenticated." }, { status: 401 });
  }

  const url = backendUrl(path.join("/")) + (req.nextUrl.search || "");
  const headers = new Headers();
  const contentType = req.headers.get("content-type");
  if (contentType) headers.set("content-type", contentType);
  headers.set("authorization", `Bearer ${token}`);

  // The client hanging up (closing a live-updates stream) cancels upstream too.
  const init: RequestInit = { method: req.method, headers, cache: "no-store", signal: req.signal };
  if (req.method !== "GET" && req.method !== "HEAD") {
    init.body = await req.text();
  }

  let upstream: Response;
  try {
    upstream = await fetch(url, init);
  } catch {
    return NextResponse.json({ detail: "Can't reach the API." }, { status: 502 });
  }

  // Live updates (Server-Sent Events): pass the stream through as it comes.
  if (upstream.headers.get("content-type")?.startsWith("text/event-stream") && upstream.body) {
    return new NextResponse(upstream.body, {
      status: upstream.status,
      headers: {
        "content-type": "text/event-stream",
        "cache-control": "no-cache, no-transform",
        "x-accel-buffering": "no",
      },
    });
  }

  // arrayBuffer (not .text()) — a JSON body round-trips through this fine,
  // but .text() re-encodes as UTF-8 on the way out and corrupts anything
  // binary, like the receipt image endpoint's JPEG bytes.
  const body = await upstream.arrayBuffer();
  return new NextResponse(body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") ?? "application/json" },
  });
}

export async function GET(req: NextRequest, ctx: Ctx) {
  return forward(req, (await ctx.params).path);
}
export async function POST(req: NextRequest, ctx: Ctx) {
  return forward(req, (await ctx.params).path);
}
export async function PATCH(req: NextRequest, ctx: Ctx) {
  return forward(req, (await ctx.params).path);
}
export async function PUT(req: NextRequest, ctx: Ctx) {
  return forward(req, (await ctx.params).path);
}
export async function DELETE(req: NextRequest, ctx: Ctx) {
  return forward(req, (await ctx.params).path);
}
