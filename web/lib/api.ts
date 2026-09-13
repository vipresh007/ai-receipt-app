export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function handle(res: Response): Promise<unknown> {
  if (!res.ok) {
    let detail = `Request failed (${res.status})`;
    try {
      const body = (await res.json()) as { detail?: string; error?: string };
      detail = body.detail ?? body.error ?? detail;
    } catch {
      /* non-JSON error body */
    }
    throw new ApiError(res.status, detail);
  }
  if (res.status === 204) return null;
  return res.json();
}

function proxyPath(path: string): string {
  return `/api/proxy/${path.replace(/^\/+/, "")}`;
}

export function apiGet<T>(path: string): Promise<T> {
  return fetch(proxyPath(path), { cache: "no-store" }).then(handle) as Promise<T>;
}

export function apiPost<T>(path: string, body: unknown): Promise<T> {
  return fetch(proxyPath(path), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  }).then(handle) as Promise<T>;
}

export function apiPut<T>(path: string, body: unknown): Promise<T> {
  return fetch(proxyPath(path), {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  }).then(handle) as Promise<T>;
}

export function apiDelete<T = null>(path: string): Promise<T> {
  return fetch(proxyPath(path), { method: "DELETE" }).then(handle) as Promise<T>;
}
