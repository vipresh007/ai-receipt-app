import type { MetadataRoute } from "next";
import { PRIVATE_PATHS, SITE_URL } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  return {
    // Every crawler, AI crawlers included: the public pages are meant to be found.
    rules: [{ userAgent: "*", allow: "/", disallow: [...PRIVATE_PATHS, "/api/", "/auth/"] }],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
