import { backendUrl } from "@/lib/backend";

export const dynamic = "force-dynamic";

/** The receipt photo behind a share link, when its owner chose to show it. */
export async function GET(_req: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const res = await fetch(backendUrl(`v1/public/splits/${encodeURIComponent(token)}/photo`), {
    cache: "no-store",
  });
  if (!res.ok || !res.body) return new Response(null, { status: res.status });
  return new Response(res.body, {
    headers: {
      "Content-Type": res.headers.get("content-type") ?? "image/jpeg",
      "Cache-Control": "private, no-store",
    },
  });
}
