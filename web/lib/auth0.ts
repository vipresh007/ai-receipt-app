import { NextResponse } from "next/server";
import { Auth0Client } from "@auth0/nextjs-auth0/server";

const baseUrl = process.env.APP_BASE_URL ?? "http://localhost:3000";

// Reads AUTH0_DOMAIN / AUTH0_CLIENT_ID / AUTH0_CLIENT_SECRET / AUTH0_SECRET /
// APP_BASE_URL from the environment. `audience` asks Auth0 for an access token
// our FastAPI backend can validate; `offline_access` gets a refresh token so the
// proxy can silently renew it.
export const auth0 = new Auth0Client({
  authorizationParameters: {
    audience: process.env.AUTH0_AUDIENCE,
    scope: "openid profile email offline_access",
  },
  // Turn a failed callback into a readable message on the landing page instead
  // of a blank 500.
  async onCallback(error, context) {
    if (error) {
      const url = new URL("/", baseUrl);
      url.searchParams.set("authError", error.message || "Authorization failed.");
      return NextResponse.redirect(url);
    }
    return NextResponse.redirect(new URL(context.returnTo || "/dashboard", baseUrl));
  },
});
