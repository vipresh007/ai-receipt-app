import { NextResponse } from "next/server";
import { backendUrl } from "@/lib/backend";

/** The confirm page's buttons: unsubscribe, then show the result. */
export async function POST(req: Request) {
  const form = await req.formData();
  const e = String(form.get("e") ?? "");
  const s = String(form.get("s") ?? "");
  const t = String(form.get("t") ?? "");
  const everything = form.get("everything") === "1";
  const res = await fetch(backendUrl("v1/public/unsubscribe"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ e, s, t, everything }),
    cache: "no-store",
  });
  const back = new URL("/unsubscribe", req.url);
  back.search = new URLSearchParams({ e, s, t, ...(res.ok ? { done: everything ? "all" : s } : {}) }).toString();
  return NextResponse.redirect(back, 303);
}
