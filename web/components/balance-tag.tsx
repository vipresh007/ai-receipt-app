import { money } from "@/lib/format";
import { cn } from "@/lib/utils";

/** "You're owed $45" / "You owe $12" / "Settled up" for a group balance
 * (positive = owed to you). */
export function balanceText(balance: string | number, currency: string, who = "You"): string {
  const n = Number(balance);
  const owe = who === "You" ? "owe" : "owes";
  if (n > 0) return `${who}${who === "You" ? "'re" : " is"} owed ${money(n, currency)}`;
  if (n < 0) return `${who} ${owe} ${money(-n, currency)}`;
  return "Settled up";
}

export function BalanceTag({
  balance,
  currency,
  who,
  className,
}: {
  balance: string | number;
  currency: string;
  who?: string;
  className?: string;
}) {
  const n = Number(balance);
  return (
    <span
      className={cn(
        "whitespace-nowrap rounded-pill px-md py-xs text-caption font-medium tabular",
        n > 0 && "bg-success-muted text-success",
        n < 0 && "bg-danger-muted text-danger",
        n === 0 && "bg-surface-2 text-text-tertiary",
        className,
      )}
    >
      {balanceText(balance, currency, who)}
    </span>
  );
}
