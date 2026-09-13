import { NextResponse, type NextRequest } from "next/server";
import { auth0 } from "@/lib/auth0";

const PROTECTED = ["/dashboard", "/receipts", "/scan", "/account", "/expenses", "/budgets"];

export async function middleware(request: NextRequest) {
  // Handles /auth/login, /auth/logout, /auth/callback, /auth/access-token, …
  // and keeps the encrypted session cookie fresh.
  const authRes = await auth0.middleware(request);

  const { pathname } = request.nextUrl;
  if (pathname.startsWith("/auth")) return authRes;

  const isProtected = PROTECTED.some(
    (p) => pathname === p || pathname.startsWith(`${p}/`),
  );
  if (isProtected) {
    const session = await auth0.getSession(request);
    if (!session) {
      const url = new URL("/auth/login", request.url);
      url.searchParams.set("returnTo", pathname);
      return NextResponse.redirect(url);
    }
  }

  return authRes;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|robots.txt).*)"],
};
