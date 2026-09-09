/** The Tally mark — a tally-of-five (four strokes + a diagonal). Uses
 *  currentColor so it inherits text color; pair it with the accent square.
 *  The viewBox is cropped tight to the art so it stays legible at small sizes. */
export function TallyMark({ size = 20, className }: { size?: number; className?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="264 258 506 506"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <g stroke="currentColor" strokeWidth={98} strokeLinecap="round">
        <line x1="344" y1="316" x2="344" y2="708" />
        <line x1="459" y1="316" x2="459" y2="708" />
        <line x1="574" y1="316" x2="574" y2="708" />
        <line x1="689" y1="316" x2="689" y2="708" />
        <line x1="316" y1="694" x2="717" y2="330" />
      </g>
    </svg>
  );
}
