import type { ReactNode } from "react";

/** Standard page heading for the signed-in app: a mono eyebrow, the title in
 * the display face, an optional one-line description, and actions on the
 * right (they wrap under the title on narrow screens). */
export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="flex flex-wrap items-end justify-between gap-lg">
      <div className="min-w-0">
        {eyebrow && (
          <p className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-text-tertiary">{eyebrow}</p>
        )}
        <h1 className="mt-xs font-display text-[34px] font-extrabold leading-[1.05] tracking-[-0.035em] md:text-[40px]">
          {title}
        </h1>
        {description && <p className="mt-sm max-w-xl text-callout text-text-secondary">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-sm">{actions}</div>}
    </header>
  );
}
