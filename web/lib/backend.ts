import "server-only";

/** Absolute URL for a backend path. Server-side only — never shipped to the browser. */
export function backendUrl(path: string): string {
  const base = process.env.BACKEND_URL ?? "http://localhost:8000";
  return `${base.replace(/\/+$/, "")}/${path.replace(/^\/+/, "")}`;
}
