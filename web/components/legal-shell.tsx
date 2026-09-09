import { readFileSync } from "fs";
import { join } from "path";
import Link from "next/link";
import { marked } from "marked";
import { TallyMark } from "@/components/tally-mark";

/** Renders one of the Markdown files in `web/content/legal/` as a page. */
export function LegalShell({ file }: { file: "privacy" | "terms" }) {
  const md = readFileSync(join(process.cwd(), "content/legal", `${file}.md`), "utf8");
  const html = marked.parse(md, { async: false, gfm: true }) as string;

  return (
    <div className="mx-auto max-w-2xl px-lg py-2xl">
      <Link
        href="/"
        className="flex items-center gap-sm text-callout font-semibold tracking-tight text-text hover:opacity-80"
      >
        <span className="grid h-7 w-7 place-items-center rounded-md bg-accent text-accent-fg">
          <TallyMark size={17} />
        </span>
        Tally
      </Link>
      <article className="legal-doc mt-xl" dangerouslySetInnerHTML={{ __html: html }} />
    </div>
  );
}
