"use client";

import { useSyncExternalStore } from "react";
import { X } from "lucide-react";
import { APP_STORE_URL } from "@/lib/site";
import { TallyMark } from "@/components/tally-mark";

const KEY = "tally:app-banner-dismissed";
const listeners = new Set<() => void>();

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Show on iPhones and iPads that haven't dismissed it. Safari also shows
 * its own Smart App Banner (the `apple-itunes-app` tag), but only until it's
 * dismissed once, and never in Chrome or Firefox on iOS. */
function shouldShow(): boolean {
  const ua = navigator.userAgent;
  const ios = /iPhone|iPad|iPod/.test(ua) || (ua.includes("Macintosh") && navigator.maxTouchPoints > 1);
  if (!ios) return false;
  try {
    return localStorage.getItem(KEY) !== "1";
  } catch {
    return true;
  }
}

function dismiss() {
  try {
    localStorage.setItem(KEY, "1");
  } catch {
    /* private mode: hides for this page view only */
  }
  hidden = true;
  listeners.forEach((l) => l());
}

let hidden = false;

/** "Tally for iPhone" prompt at the top of the web app on iOS. */
export function AppDownloadBanner() {
  const show = useSyncExternalStore(
    subscribe,
    () => !hidden && shouldShow(),
    () => false, // server render: nothing, so the first paint matches
  );
  if (!show) return null;

  return (
    <div className="flex items-center gap-md rounded-lg bg-surface p-sm pl-md ring-1 ring-border">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-[9px] bg-hero text-gold ring-1 ring-white/5">
        <TallyMark size={17} />
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-callout font-semibold">Tally for iPhone</p>
        <p className="truncate text-caption text-text-secondary">Faster scanning, right from your camera</p>
      </div>
      <a
        href={APP_STORE_URL}
        className="rounded-pill bg-accent px-lg py-xs text-caption font-semibold text-accent-fg"
      >
        Get
      </a>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dismiss"
        className="grid h-8 w-8 place-items-center rounded-full text-text-tertiary hover:bg-surface-2"
      >
        <X size={16} />
      </button>
    </div>
  );
}
