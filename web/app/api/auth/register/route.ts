import { type NextRequest, NextResponse } from "next/server";
import { backendUrl } from "@/lib/backend";
import { setSession } from "@/lib/session";
import type { TokenOut } from "@/lib/types";

export async function POST(req: NextRequest) {
  const payload = await req.text();

  let upstream: Response;
  try {
    upstream = await fetch(backendUrl("v1/auth/register"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: payload,
      cache: "no-store",
    });
  } catch {
    return NextResponse.json({ detail: "Can't reach the API." }, { status: 502 });
  }

  if (!upstream.ok) {
    const text = await upstream.text();
    return new NextResponse(text || JSON.stringify({ detail: "Sign up failed." }), {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  }

  const token = (await upstream.json()) as TokenOut;
  await setSession(token.access_token, token.expires_in);
  return NextResponse.json({ ok: true });
}
