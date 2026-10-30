"use client";

import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";

/** One open Server-Sent Events stream while the app is open. When the server
 * says something of yours changed (someone added, edited, paid, commented),
 * refetch whatever is on screen. No polling. */
export function LiveUpdates() {
  const queryClient = useQueryClient();

  useEffect(() => {
    let source: EventSource | null = null;
    let pending: ReturnType<typeof setTimeout> | undefined;

    const refresh = () => {
      // A burst of changes (a save touches several things) → one refetch.
      clearTimeout(pending);
      pending = setTimeout(() => queryClient.invalidateQueries(), 250);
    };
    const connect = () => {
      source?.close();
      source = new EventSource("/api/proxy/v1/events");
      source.addEventListener("changed", refresh);
    };
    // The browser reconnects a dropped stream by itself; one it gave up on
    // (signed out, server restarting) is reopened when you come back.
    const onVisible = () => {
      if (document.visibilityState !== "visible") return;
      if (!source || source.readyState === EventSource.CLOSED) connect();
    };

    connect();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearTimeout(pending);
      source?.close();
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [queryClient]);

  return null;
}
