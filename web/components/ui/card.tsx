import { cn } from "@/lib/utils";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn("rounded-xl bg-surface p-2xl shadow-e1 ring-1 ring-border", className)}
      {...props}
    />
  );
}

/** Section label, set like the landing page's printed eyebrows. */
export function CardTitle({ className, ...props }: React.HTMLAttributes<HTMLHeadingElement>) {
  return (
    <h3
      className={cn(
        "font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-text-tertiary",
        className,
      )}
      {...props}
    />
  );
}
