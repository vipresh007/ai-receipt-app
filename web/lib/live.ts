/** For data other people change too (shared expenses, groups, people,
 * activity). It isn't polled: the server pushes "something changed" over the
 * live-updates stream (components/live-updates.tsx), which refetches whatever
 * is on screen. Coming back to the tab refetches too, in case anything was
 * missed while the stream was asleep. */
export const LIVE = {
  staleTime: 0,
  refetchOnWindowFocus: true,
} as const;
