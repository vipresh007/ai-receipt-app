import { readFileSync } from "fs";
import { join } from "path";
import { marked } from "marked";
import { auth0 } from "@/lib/auth0";
import { SiteFooter, SiteHeader } from "@/components/landing";

/** Renders one of the Markdown files in `web/content/legal/` as a page, in the
 * landing page's ink "ledger" look with the same header and footer. */
export async function LegalShell({ file }: { file: "privacy" | "terms" }) {
  const md = readFileSync(join(process.cwd(), "content/legal", `${file}.md`), "utf8");
  const html = marked.parse(md, { async: false, gfm: true }) as string;
  const session = await auth0.getSession();

  return (
    <div className="ledger min-h-dvh">
      <SiteHeader isSignedIn={!!session} />
      <main className="px-6 pb-24 pt-16 lg:pb-32 lg:pt-24">
        <article
          className="legal-doc mx-auto max-w-[720px]"
          dangerouslySetInnerHTML={{ __html: html }}
        />
      </main>
      <SiteFooter />
    </div>
  );
}
