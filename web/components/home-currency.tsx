"use client";

import { useEffect } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { apiGet } from "@/lib/api";
import { getHomeCurrency, guessCurrency, setHomeCurrency } from "@/lib/format";
import type { Me } from "@/lib/types";

/** Keeps amounts in the account's home currency: set under Account, else the
 * one your receipts use most, else a guess from this device (no location
 * prompt). Renders nothing. */
export function HomeCurrency() {
  const queryClient = useQueryClient();
  const { data: me } = useQuery({ queryKey: ["me"], queryFn: () => apiGet<Me>("v1/auth/me") });

  useEffect(() => {
    const next = me?.currency || guessCurrency();
    if (next !== getHomeCurrency()) {
      setHomeCurrency(next);
      // Redraw what's on screen in the new currency.
      void queryClient.invalidateQueries({ predicate: (q) => q.queryKey[0] !== "me" });
    }
  }, [me?.currency, queryClient]);

  return null;
}
