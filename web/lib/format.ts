export function money(value: string | number, currency = "USD"): string {
  const n = typeof value === "string" ? Number(value) : value;
  if (!Number.isFinite(n)) return "—";
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: currency || "USD" }).format(n);
  } catch {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: "USD" }).format(n);
  }
}

export function shortDate(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso.length === 10 ? `${iso}T00:00:00` : iso);
  if (Number.isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(d);
}

/** A decimal-string amount as whole cents. Unparseable or partial input
 * ("", ".") counts as 0, so a value typed one keystroke at a time adds up. */
export function toCents(value: string): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
}

/** Whole cents back to the 2-decimal string the API takes. */
export function fromCents(cents: number): string {
  return (cents / 100).toFixed(2);
}
